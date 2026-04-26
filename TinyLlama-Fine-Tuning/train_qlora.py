import os
os.environ["TRANSFORMERS_NO_TF"] = "1"
os.environ["TRANSFORMERS_NO_FLAX"] = "1"

import torch
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling,
)
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training, TaskType
from datasets import load_from_disk


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_NAME = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
DATASET_PATH = os.path.join(SCRIPT_DIR, "squat_dataset_tinyllama")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "tinyllama-1.1b-squat-qlora-chat")
MAX_SEQ_LENGTH = 512

LORA_R = 16
LORA_ALPHA = 32
LORA_DROPOUT = 0.05
TARGET_MODULES = ["q_proj", "k_proj", "v_proj", "o_proj"]

BATCH_SIZE = 1
GRADIENT_ACCUMULATION_STEPS = 8
LEARNING_RATE = 2e-4
NUM_EPOCHS = 3
WARMUP_STEPS = 50
SAVE_STEPS = 100
LOGGING_STEPS = 10
EVAL_STEPS = 100


device = "cuda" if torch.cuda.is_available() else "cpu"
if device != "cuda":
    raise SystemExit("CUDA GPU is required for this Colab QLoRA script.")

print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")

print(f"\n[1/6] Loading tokenizer: {MODEL_NAME}")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)

if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.pad_token_id = tokenizer.eos_token_id
    tokenizer.padding_side = "left"

print(f"\n[2/6] Preparing 4-bit quantization config")
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=True,
)

print(f"[3/6] Loading base model in 4-bit on single GPU")
# IMPORTANT: For 4-bit bitsandbytes models we must avoid Accelerate's
# dispatch_model(...), which calls model.to(device) and raises:
# "`.to` is not supported for `4-bit` or `8-bit` bitsandbytes models."
# We do this by not providing a device_map and forcing low_cpu_mem_usage=False
# so the model stays on the default CUDA device.
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    quantization_config=bnb_config,
    device_map=None,
    trust_remote_code=True,
    torch_dtype=torch.float16,
    low_cpu_mem_usage=False,
)

print(f"[4/6] Preparing model for k-bit (QLoRA)")
model = prepare_model_for_kbit_training(model)

print(f"[5/6] Attaching LoRA adapters")
lora_config = LoraConfig(
    r=LORA_R,
    lora_alpha=LORA_ALPHA,
    target_modules=TARGET_MODULES,
    lora_dropout=LORA_DROPOUT,
    bias="none",
    task_type=TaskType.CAUSAL_LM,
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
model.gradient_checkpointing_enable()
print("Gradient checkpointing enabled")

print(f"\n[6/6] Loading dataset from {DATASET_PATH}...")
try:
    dataset = load_from_disk(DATASET_PATH)
    print(f"Dataset loaded: {len(dataset)} samples")
except Exception as e:
    print(f"Error loading dataset: {e}")
    raise SystemExit(1)

if "train" not in dataset:
    dataset = dataset.train_test_split(test_size=0.2, seed=42)
    train_dataset = dataset["train"]
    eval_dataset = dataset["test"]
else:
    train_dataset = dataset["train"]
    eval_dataset = dataset.get("validation", dataset["test"] if "test" in dataset else None)

print(f"Train samples: {len(train_dataset)}")
print(f"Validation samples: {len(eval_dataset) if eval_dataset else 0}")

data_collator = DataCollatorForLanguageModeling(
    tokenizer=tokenizer,
    mlm=False,
)

training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    overwrite_output_dir=True,
    num_train_epochs=NUM_EPOCHS,
    per_device_train_batch_size=BATCH_SIZE,
    per_device_eval_batch_size=1,
    gradient_accumulation_steps=GRADIENT_ACCUMULATION_STEPS,
    gradient_checkpointing=True,
    learning_rate=LEARNING_RATE,
    warmup_steps=WARMUP_STEPS,
    logging_steps=LOGGING_STEPS,
    save_steps=SAVE_STEPS,
    eval_steps=EVAL_STEPS,
    evaluation_strategy="steps" if eval_dataset else "no",
    save_total_limit=3,
    load_best_model_at_end=True if eval_dataset else False,
    metric_for_best_model="loss" if eval_dataset else None,
    greater_is_better=False,
    fp16=True,
    optim="paged_adamw_8bit",
    report_to=[],
    max_steps=-1,
    dataloader_pin_memory=False,
    remove_unused_columns=False,
)


class QLoRATrainer(Trainer):
    # Prevent Trainer/Accelerate from calling model.to(device) on 4-bit models
    def _move_model_to_device(self, model, device):
        return model


trainer = QLoRATrainer(
    model=model,
    args=training_args,
    train_dataset=train_dataset,
    eval_dataset=eval_dataset,
    data_collator=data_collator,
    tokenizer=tokenizer,
)

checkpoint_dir = None
if os.path.exists(OUTPUT_DIR):
    checkpoints = [d for d in os.listdir(OUTPUT_DIR) if d.startswith("checkpoint-")]
    if checkpoints:
        latest_checkpoint = max(checkpoints, key=lambda x: int(x.split("-")[1]))
        checkpoint_dir = os.path.join(OUTPUT_DIR, latest_checkpoint)
        print("\n" + "=" * 50)
        print(f"Found existing checkpoint: {latest_checkpoint}")
        print("Training will RESUME from this checkpoint")
        print("=" * 50)
    else:
        print("\n" + "=" * 50)
        print("No existing checkpoints found")
        print("Starting NEW training")
        print("=" * 50)
else:
    print("\n" + "=" * 50)
    print("Starting NEW training")
    print("=" * 50)

print(f"Effective batch size: {BATCH_SIZE * GRADIENT_ACCUMULATION_STEPS}")
print(f"Total steps: {len(train_dataset) // (BATCH_SIZE * GRADIENT_ACCUMULATION_STEPS) * NUM_EPOCHS}")

trainer.train(resume_from_checkpoint=checkpoint_dir)

print("\nTraining completed successfully!")
print(f"\nSaving final model to {OUTPUT_DIR}...")
trainer.save_model()
tokenizer.save_pretrained(OUTPUT_DIR)
print(f"\nModel saved to: {OUTPUT_DIR}")