# Mistral-7B-Instruct QLoRA Fine-tuning for Squat Analysis

This directory contains scripts for fine-tuning Mistral-7B-Instruct-v0.2 with QLoRA on squat form analysis data.

## Hardware Requirements

- **GPU**: 6GB+ VRAM (optimized for 6GB)
- **RAM**: 16GB+ recommended
- **Storage**: ~20GB for model and data

## Setup

1. **Install dependencies:**
```bash
pip install -r requirements.txt
```

2. **Verify GPU:**
```bash
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"None\"}')"
```

## Usage

### Step 1: Preprocess Data

Convert CSV to HuggingFace Dataset format:

```bash
cd Fine-Tuning
python preprocess_data.py
```

This will:
- Load `SquatTrainingDataset.csv`
- Format data according to Mistral chat template
- Tokenize and save dataset to `squat_dataset/`

### Step 2: Train Model

Start training with QLoRA:

```bash
python train_qlora.py
```

**Training Configuration (optimized for 6GB VRAM):**
- Batch size: 1
- Gradient accumulation: 8 (effective batch size = 8)
- Max sequence length: 1024
- LoRA rank: 16
- Learning rate: 2e-4
- Epochs: 3

**Expected Training Time:**
- ~2-4 hours for 1500 samples on 6GB GPU (depending on GPU model)

**Memory Usage:**
- Model (4-bit): ~4.5GB
- Training overhead: ~1.5GB
- Total: ~6GB

### Step 3: Test Inference

Test the fine-tuned model:

```bash
python inference.py
```

## Troubleshooting

### Out of Memory (OOM) Errors

If you encounter OOM errors, try:

1. **Reduce sequence length** in `train_qlora.py`:
   ```python
   MAX_SEQ_LENGTH = 512  # Instead of 1024
   ```

2. **Reduce gradient accumulation**:
   ```python
   GRADIENT_ACCUMULATION_STEPS = 4  # Instead of 8
   ```

3. **Reduce LoRA rank**:
   ```python
   LORA_R = 8  # Instead of 16
   ```

4. **Close other GPU applications**

### Slow Training

- Training is slower with gradient checkpointing (necessary for 6GB VRAM)
- This is normal and expected
- Consider using a cloud GPU (Colab Pro, RunPod, etc.) for faster training

### Model Not Loading

- Ensure you've completed Step 1 (preprocessing)
- Check that `squat_dataset/` directory exists
- Verify CSV file is in the correct format

## Output

After training, you'll have:
- `mistral-7b-squat-qlora/` - Fine-tuned LoRA weights
- `mistral-7b-squat-qlora/logs/` - TensorBoard logs

## Integration

To use the fine-tuned model in your Streamlit app:

1. Load the model using `inference.py` as reference
2. Format inputs according to your CSV structure
3. Parse outputs (split by `|||` for direct answer and details)

## Files

- `preprocess_data.py` - Data preprocessing script
- `train_qlora.py` - QLoRA training script
- `inference.py` - Inference/testing script
- `SquatTrainingDataset.csv` - Training data
- `requirements.txt` - Python dependencies



