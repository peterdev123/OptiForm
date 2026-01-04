C"""
Inference script for fine-tuned Mistral-7B-Instruct model
"""

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import PeftModel
import sys

# Configuration
import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.2"
# Use the final checkpoint (best validation loss)
LORA_WEIGHTS = os.path.join(SCRIPT_DIR, "mistral-7b-squat-qlora", "checkpoint-450")

def load_model_and_tokenizer(base_model, lora_weights):
    """Load base model and LoRA weights"""
    print(f"Loading tokenizer from {base_model}...")
    tokenizer = AutoTokenizer.from_pretrained(base_model, trust_remote_code=True)
    
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.pad_token_id = tokenizer.eos_token_id
    
    print(f"Loading base model with 4-bit quantization...")
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
    )
    
    model = AutoModelForCausalLM.from_pretrained(
        base_model,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True,
        torch_dtype=torch.float16,
    )
    
    print(f"Loading LoRA weights from {lora_weights}...")
    model = PeftModel.from_pretrained(model, lora_weights)
    model.eval()
    
    return model, tokenizer

def format_prompt(instruction, input_text):
    """Format prompt according to Mistral template"""
    if instruction.startswith('"') and instruction.endswith('"'):
        instruction = instruction[1:-1]
    elif instruction.startswith("'") and instruction.endswith("'"):
        instruction = instruction[1:-1]
    
    prompt = f"<s>[INST] {instruction}\n\n{input_text} [/INST]"
    return prompt

def generate_response(model, tokenizer, prompt, max_new_tokens=256, temperature=0.7, top_p=0.9):
    """Generate response from model"""
    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            temperature=temperature,
            top_p=top_p,
            do_sample=True,
            pad_token_id=tokenizer.eos_token_id,
        )
    
    # Decode only the new tokens (response)
    response = tokenizer.decode(outputs[0][inputs.input_ids.shape[1]:], skip_special_tokens=True)
    return response.strip()

if __name__ == "__main__":
    # Load model
    print("Loading model...")
    model, tokenizer = load_model_and_tokenizer(BASE_MODEL, LORA_WEIGHTS)
    print("Model loaded successfully!\n")
    
    # Example usage
    instruction = "You are an expert fitness trainer and biomechanics specialist on back squat. Analyze back squat form data. Provide corrective feedback considering form issues, body type, and measurements. Give actionable recommendations."
    
    # Example input
    input_text = """Body Type: Longer Legs
Heels Lifting: TRUE (35696ms, torso-hip: 35, ankle: 54, heel: 40)
Torso Forward: FALSE
Knees Forward: TRUE (35696ms, torso-hip: 35, ankle: 54, heel: 40)
Elbow Flaring: TRUE (17)
Depth: 45
Acceptable: FALSE"""
    
    prompt = format_prompt(instruction, input_text)
    
    print("=" * 50)
    print("Generating response...")
    print("=" * 50)
    print(f"Input:\n{input_text}\n")
    
    response = generate_response(model, tokenizer, prompt)
    
    print("=" * 50)
    print("Response:")
    print("=" * 50)
    print(response)
    
    # Interactive mode
    print("\n" + "=" * 50)
    print("Interactive mode (type 'quit' to exit)")
    print("=" * 50)
    
    while True:
        try:
            user_input = input("\nEnter form data (or 'quit'): ")
            if user_input.lower() == 'quit':
                break
            
            prompt = format_prompt(instruction, user_input)
            response = generate_response(model, tokenizer, prompt)
            print(f"\nResponse:\n{response}\n")
            
        except KeyboardInterrupt:
            print("\nExiting...")
            break
        except Exception as e:
            print(f"Error: {e}")

