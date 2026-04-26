import os
import pandas as pd
from datasets import Dataset
from transformers import AutoTokenizer


def format_chat_prompt(system_message: str, user_prompt: str, assistant_output: str) -> str:
    system_message = str(system_message).strip().strip('"').strip("'")
    user_prompt = str(user_prompt).strip()
    assistant_output = str(assistant_output).strip()
    return (
        "<|system|>\n"
        f"{system_message}</s>\n"
        "<|user|>\n"
        f"{user_prompt}</s>\n"
        "<|assistant|>\n"
        f"{assistant_output}"
    )


def prepare_dataset(csv_path: str, tokenizer: AutoTokenizer, max_length: int = 512):
    print(f"Loading CSV from {csv_path}...")
    df = pd.read_csv(csv_path)
    print(f"Found {len(df)} rows")

    print("Formatting prompts...")
    texts = []
    for idx, row in df.iterrows():
        prompt = format_chat_prompt(row["instruction"], row["input"], row["output"])
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
            return_tensors=None,
        )
        tokenized["labels"] = tokenized["input_ids"].copy()
        return tokenized

    tokenized_dataset = dataset.map(
        tokenize_function,
        batched=True,
        remove_columns=["text"],
        desc="Tokenizing",
    )

    print(f"Dataset prepared: {len(tokenized_dataset)} samples")
    return tokenized_dataset


if __name__ == "__main__":
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

    model_name = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
    # source CSV stays in original Fine-Tuning folder
    csv_path = os.path.join(SCRIPT_DIR, "..", "Fine-Tuning", "SquatTrainingDatasetRefactored.csv")

    print(f"Loading tokenizer: {model_name}")
    tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)

    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.pad_token_id = tokenizer.eos_token_id

    dataset = prepare_dataset(csv_path, tokenizer, max_length=512)

    output_path = os.path.join(SCRIPT_DIR, "squat_dataset_tinyllama")
    print(f"Saving dataset to {output_path}...")
    dataset.save_to_disk(output_path)
    print("Dataset saved successfully!")

