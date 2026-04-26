"""
Data preprocessing script for TinyLlama fine-tuning.
Converts CSV to HuggingFace Dataset format with a simple instruction/input/output template.
"""

import pandas as pd
from datasets import Dataset
from transformers import AutoTokenizer

def format_prompt(instruction, input_text, output_text):
    instruction = str(instruction).strip()
    if instruction.startswith('"') and instruction.endswith('"'):
        instruction = instruction[1:-1]
    elif instruction.startswith("'") and instruction.endswith("'"):
        instruction = instruction[1:-1]
    prompt = (
        f"Instruction: {instruction}\n\n"
        f"Input:\n{input_text}\n\n"
        f"Output:\n{output_text}"
    )
    return prompt

def prepare_dataset(csv_path, tokenizer, max_length=512):
    """
    Load CSV and convert to HuggingFace Dataset format.
    
    Args:
        csv_path: Path to CSV file
        tokenizer: Tokenizer instance
        max_length: Maximum sequence length
    """
    print(f"Loading CSV from {csv_path}...")
    df = pd.read_csv(csv_path)
    
    print(f"Found {len(df)} rows")
    print("Formatting prompts...")
    texts = []
    for idx, row in df.iterrows():
        prompt = format_prompt(
            row['instruction'],
            row['input'],
            row['output']
        )
        texts.append(prompt)
        
        if (idx + 1) % 100 == 0:
            print(f"Processed {idx + 1}/{len(df)} rows...")
    
    dataset = Dataset.from_dict({"text": texts})
    
    print("Tokenizing dataset...")
    def tokenize_function(examples):
        tokenized = tokenizer(
            examples["text"],
            truncation=True,
            max_length=max_length,
            padding=False,
            return_tensors=None
        )
        # For causal LM, labels are the same as input_ids
        tokenized["labels"] = tokenized["input_ids"].copy()
        return tokenized
    
    tokenized_dataset = dataset.map(
        tokenize_function,
        batched=True,
        remove_columns=["text"],
        desc="Tokenizing"
    )
    
    print(f"Dataset prepared: {len(tokenized_dataset)} samples")
    return tokenized_dataset

if __name__ == "__main__":
    import os
    
    model_name = "mistralai/Mistral-7B-Instruct-v0.2"
    script_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(script_dir, "SquatTrainingDatasetRefactored.csv")
    
    print(f"Loading tokenizer: {model_name}")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    
    # Set pad token if not present
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.pad_token_id = tokenizer.eos_token_id
    
    # Prepare dataset
    dataset = prepare_dataset(csv_path, tokenizer, max_length=512)
    
    # Save dataset
    output_path = os.path.join(script_dir, "squat_dataset")
    print(f"Saving dataset to {output_path}...")
    dataset.save_to_disk(output_path)
    print("Dataset saved successfully!")
    
    # Print sample
    print("\nSample tokenized example:")
    print(f"Input IDs length: {len(dataset[0]['input_ids'])}")
    print(f"Decoded sample:")
    print(tokenizer.decode(dataset[0]['input_ids'][:200]))

