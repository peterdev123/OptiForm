## TinyLlama Fine-Tuning Setup

This folder contains a self‑contained pipeline to fine‑tune **TinyLlama‑1.1B‑Chat** on your squat form dataset, using a simple chat template that is friendly for future mobile/on‑device deployment.

---

### 1. Goal

Train a **small chat model** that:

- Takes your **form summary text** (Body Type, Heels, Knees, etc.).
- Generates **short, actionable feedback**.
- Is small enough (1.1B params, 4‑bit) to:
  - Run comfortably on a **6 GB GPU**.
  - Be a realistic candidate for **future mobile/on‑device** use after quantization.

---

### 2. Data format

Source CSV (already prepared):  
`Fine-Tuning/SquatTrainingDatasetRefactored.csv`

Columns:

- `instruction`: high‑level instruction text (shortened).
- `input`: multi‑line form summary (Body Type, Heels, Torso, Knees, Elbows, Depth, Acceptable).
- `output`: target feedback sentence(s).

Each row is converted into a **single chat example** with this template:

```text
<|system|>
{instruction}</s>
<|user|>
{input}</s>
<|assistant|>
{output}
```

Where:

- `{instruction}` → `instruction` column (system message).
- `{input}` → `input` column (user prompt).
- `{output}` → `output` column (assistant reply).

---

### 3. Preprocessing (`preprocess.py`)

File: `TinyLlama-Fine-Tuning/preprocess.py`

**Libraries used**

- **`pandas`**: read `SquatTrainingDatasetRefactored.csv`.
- **`datasets`** (Hugging Face): build and save a tokenized dataset that `transformers` can load efficiently.
- **`transformers`**: `AutoTokenizer` for TinyLlama, used to convert text into token IDs.

**Main steps**

1. **Load CSV**
   - Path: `../Fine-Tuning/SquatTrainingDatasetRefactored.csv`.
   - Columns: `instruction`, `input`, `output`.

2. **Format chat prompts**
   - For each row, `format_chat_prompt()` builds the string in the chat template above.
   - All such strings are collected into a list.

3. **Create a `datasets.Dataset`**
   - `Dataset.from_dict({"text": texts})`

4. **Tokenize**
   - The tokenizer for `TinyLlama/TinyLlama-1.1B-Chat-v1.0` encodes each `text`:
     - `truncation=True`, `max_length=512`, no padding.
   - For causal LM, `labels = input_ids`.

5. **Save**
   - Saved to: `TinyLlama-Fine-Tuning/squat_dataset_tinyllama/`
   - This directory is later consumed by the training script.

To run:

```bash
cd TinyLlama-Fine-Tuning
python preprocess.py
```

---

### 4. Training (`train_qlora.py`)

File: `TinyLlama-Fine-Tuning/train_qlora.py`

This script performs **QLoRA fine‑tuning** of TinyLlama on the preprocessed dataset.

**Libraries used**

- **`torch`**: core deep learning and GPU support.
- **`transformers`**:
  - `AutoModelForCausalLM`: loads TinyLlama base model.
  - `AutoTokenizer`: (for completeness; already used in preprocessing).
  - `BitsAndBytesConfig`: configure 4‑bit quantization.
  - `TrainingArguments`, `Trainer`: training loop configuration and runner.
  - `DataCollatorForLanguageModeling`: builds LM batches (shifts labels automatically).
- **`peft`**:
  - `LoraConfig`, `get_peft_model`: define and attach LoRA adapters.
  - `prepare_model_for_kbit_training`: make the quantized model trainable.
  - `TaskType.CAUSAL_LM`: defines the task type.
- **`datasets`**:
  - `load_from_disk`: load the tokenized dataset saved by `preprocess.py`.

**Model & dataset paths**

- `MODEL_NAME = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"`
- `DATASET_PATH = "TinyLlama-Fine-Tuning/squat_dataset_tinyllama"`
- `OUTPUT_DIR = "TinyLlama-Fine-Tuning/tinyllama-1.1b-squat-qlora-chat"`

**Quantization (QLoRA)**

- Uses `BitsAndBytesConfig`:
  - `load_in_4bit=True`
  - `bnb_4bit_quant_type="nf4"`
  - `bnb_4bit_compute_dtype=torch.float16`
  - `bnb_4bit_use_double_quant=True`
- Loads TinyLlama in 4‑bit:

  ```python
  model = AutoModelForCausalLM.from_pretrained(
      MODEL_NAME,
      quantization_config=bnb_config,
      device_map="auto",
      trust_remote_code=True,
      torch_dtype=torch.float16,
  )
  ```

- `prepare_model_for_kbit_training(model)` adapts it for training with 4‑bit weights.

**LoRA configuration**

- `LoraConfig`:
  - `r = 16` (rank)
  - `lora_alpha = 32`
  - `lora_dropout = 0.05`
  - `target_modules = ["q_proj", "k_proj", "v_proj", "o_proj"]`
  - `task_type = TaskType.CAUSAL_LM`

Only these small LoRA matrices are trained; the base TinyLlama weights stay frozen.

**Training hyperparameters**

- Epochs: `NUM_EPOCHS = 3`
- Per‑device batch size: `BATCH_SIZE = 1`
- Gradient accumulation: `GRADIENT_ACCUMULATION_STEPS = 8`  
  → Effective batch size = 8.
- Learning rate: `LEARNING_RATE = 2e-4`
- Warmup steps: `WARMUP_STEPS = 50`
- Max sequence length: `MAX_SEQ_LENGTH = 512`
- Optimization:
  - `fp16=True`
  - `optim="paged_adamw_8bit"`
  - `gradient_checkpointing=True` (reduces memory usage)

**Evaluation / saving**

- `save_steps = 100`, `eval_steps = 100`
- `evaluation_strategy="steps"` if eval split exists.
- `save_total_limit = 3` (keep last 3 checkpoints).
- `metric_for_best_model="loss"`, `greater_is_better=False`

**Custom Trainer**

Because the model is 4‑bit quantized, we define:

```python
class QLoRATrainer(Trainer):
    def _move_model_to_device(self, model, device):
        return model
```

This avoids `Trainer` calling `model.to(device)`, which is not supported on bitsandbytes 4‑bit models. `device_map="auto"` from `from_pretrained` already placed the model correctly.

**Train flow**

1. Load TinyLlama in 4‑bit and attach LoRA.
2. Load dataset from `squat_dataset_tinyllama`.
3. Split into train/test (80/20) if needed.
4. Build `TrainingArguments` and `QLoRATrainer`.
5. Call `trainer.train(...)`, optionally resuming from an existing checkpoint.
6. Save final adapter to `tinyllama-1.1b-squat-qlora-chat/` along with tokenizer.

To run:

```bash
cd TinyLlama-Fine-Tuning
python preprocess.py
python train_qlora.py
```

---

### 5. How this fits your project

- Uses **the same squat dataset** and refactored CSV as your Mistral setup.
- Uses a **chat‑style template** that’s natural for TinyLlama‑Chat and later GGUF/Llama.cpp runtimes.
- Produces a **small LoRA adapter** on top of TinyLlama‑1.1B:
  - Easier to run on your **local 6 GB GPU**.
  - Better aligned with **future mobile/on‑device** deployment (after export to GGUF or similar).


