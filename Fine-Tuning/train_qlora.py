"""
QLoRA Fine-tuning script for Mistral-7B-Instruct-v0.2
Optimized for 6GB VRAM GPU
"""

import torch
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling
)
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training, TaskType
from datasets import load_from_disk
import os
import gc

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_NAME = "mistralai/Mistral-7B-Instruct-v0.2"
DATASET_PATH = os.path.join(SCRIPT_DIR, "squat_dataset")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "mistral-7b-squat-qlora")
MAX_SEQ_LENGTH = 1024  


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
if device == "cuda":
    print(f"GPU: {torch.cuda.get_device_name(0)}")
    print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
else:
    exit(1)

# Load tokenizer from squat_dataset
print(f"\n[1/6] Loading tokenizer: {MODEL_NAME}")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)

if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.pad_token_id = tokenizer.eos_token_id
    tokenizer.padding_side = "left"


print(f"\n[2/6]")
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16, 
    bnb_4bit_use_double_quant=True, 
)

# Load model with 4-bit quantization
print(f"[3/6]")
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    quantization_config=bnb_config,
    device_map="auto",
    trust_remote_code=True,
    torch_dtype=torch.float16,
)

print(f"[4/6]")
model = prepare_model_for_kbit_training(model)

print(f"[5/6]")
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
    print("Please run preprocess_data.py first to prepare the dataset.")
    exit(1)

# Split dataset (80% train, 20% validation)
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
    eval_strategy="steps" if eval_dataset else "no",
    save_total_limit=3, 
    load_best_model_at_end=True if eval_dataset else False,
    metric_for_best_model="loss" if eval_dataset else None,
    greater_is_better=False,
    fp16=True, 
    optim="paged_adamw_8bit", 
    report_to="tensorboard",
    logging_dir=f"{OUTPUT_DIR}/logs",
    max_steps=-1, 
    dataloader_pin_memory=False,  
    remove_unused_columns=False,
)

trainer = Trainer(
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
        
        # Pre-emptively handle PyTorch 2.6 requirement by backing up torch.load files
        import shutil
        torch_files = ["optimizer.pt", "scheduler.pt", "scaler.pt", "rng_state.pth"]
        backed_up = []
        for file in torch_files:
            file_path = os.path.join(checkpoint_dir, file)
            if os.path.exists(file_path):
                backup_path = file_path + ".backup"
                if not os.path.exists(backup_path):  # Only backup if not already backed up
                    shutil.move(file_path, backup_path)
                    backed_up.append(file)
        
        if backed_up:
            print(f"\nNote: Backed up PyTorch state files ({', '.join(backed_up)})")
            print("due to PyTorch version requirements. Optimizer will reinitialize.")
            print("Model weights are preserved.\n")
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

# Pre-emptively handle PyTorch 2.6 requirement by backing up torch.load files
if checkpoint_dir and os.path.exists(checkpoint_dir):
    import shutil
    torch_files = ["optimizer.pt", "scheduler.pt", "scaler.pt", "rng_state.pth"]
    backed_up = []
    for file in torch_files:
        file_path = os.path.join(checkpoint_dir, file)
        if os.path.exists(file_path):
            backup_path = file_path + ".backup"
            shutil.move(file_path, backup_path)
            backed_up.append(file)
    
    if backed_up:
        print("\n" + "=" * 60)
        print("WARNING: PyTorch version compatibility")
        print("=" * 60)
        print("PyTorch 2.6+ required for loading optimizer/scheduler state.")
        print(f"Backed up files: {', '.join(backed_up)}")
        print("Training will continue with model weights but reinitialize optimizer.")
        print("=" * 60 + "\n")

try:
    # Try to resume from checkpoint
    trainer.train(resume_from_checkpoint=checkpoint_dir)
except ValueError as e:
    if "torch.load" in str(e) and "v2.6" in str(e):
        print("\n" + "=" * 60)
        print("ERROR: PyTorch version requirement not met")
        print("=" * 60)
        print("PyTorch 2.6+ is required but not available.")
        print("Options:")
        print("1. Wait for PyTorch 2.6 release and upgrade")
        print("2. Start training from scratch (delete checkpoint-100 folder)")
        print("3. Use a different checkpoint that doesn't require torch.load")
        print("=" * 60)
        raise
    else:
        raise
    print("\nTraining completed successfully!")
    
    print(f"\nSaving final model to {OUTPUT_DIR}...")
    trainer.save_model()
    tokenizer.save_pretrained(OUTPUT_DIR)
    
    print(f"\nModel saved to: {OUTPUT_DIR}")
    
except RuntimeError as e:
    if "out of memory" in str(e).lower():
        print("\n" + "=" * 50)
        print("OUT OF MEMORY ERROR!")
        print("=" * 50)
        print("Try the following:")
        print("1. Reduce MAX_SEQ_LENGTH to 512")
        print("2. Reduce GRADIENT_ACCUMULATION_STEPS to 4")
        print("3. Reduce LORA_R to 8")
        print("4. Close other applications using GPU")
    raise

if torch.cuda.is_available():
    print(f"\nMemory after training:")
    print(f"Allocated: {torch.cuda.memory_allocated(0) / 1e9:.2f} GB")
    print(f"Reserved: {torch.cuda.memory_reserved(0) / 1e9:.2f} GB")

