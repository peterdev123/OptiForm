"""
LLM Feedback Generator for Streamlit Integration
Loads the fine-tuned model and generates feedback from form summaries
"""

import os
import sys
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import PeftModel

# Add Fine-Tuning directory to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FINE_TUNING_DIR = os.path.join(SCRIPT_DIR, "Fine-Tuning")
sys.path.append(FINE_TUNING_DIR)

BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.2"
LORA_WEIGHTS = os.path.join(FINE_TUNING_DIR, "mistral-7b-squat-qlora", "checkpoint-450")

# Global model instance (singleton pattern)
_model = None
_tokenizer = None

def load_llm_model():
    """Load the fine-tuned LLM model (singleton pattern)"""
    global _model, _tokenizer
    
    if _model is not None and _tokenizer is not None:
        return _model, _tokenizer
    
    try:
        print("Loading fine-tuned model...")
        tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL, trust_remote_code=True)
        
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
            tokenizer.pad_token_id = tokenizer.eos_token_id
        
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,
        )
        
        model = AutoModelForCausalLM.from_pretrained(
            BASE_MODEL,
            quantization_config=bnb_config,
            device_map="auto",
            trust_remote_code=True,
            torch_dtype=torch.float16,
        )
        
        model = PeftModel.from_pretrained(model, LORA_WEIGHTS)
        model.eval()
        
        # Compile model for faster inference (PyTorch 2.0+)
        try:
            model = torch.compile(model, mode="reduce-overhead")
            print("Model compiled for faster inference")
        except:
            print("Model compilation not available (requires PyTorch 2.0+)")
        
        _model = model
        _tokenizer = tokenizer
        
        print("Model loaded successfully!")
        return model, tokenizer
    except Exception as e:
        print(f"Error loading model: {e}")
        return None, None

def format_prompt(instruction, input_text):
    """Format prompt according to Mistral template"""
    if instruction.startswith('"') and instruction.endswith('"'):
        instruction = instruction[1:-1]
    elif instruction.startswith("'") and instruction.endswith("'"):
        instruction = instruction[1:-1]
    
    prompt = f"<s>[INST] {instruction}\n\n{input_text} [/INST]"
    return prompt

def generate_feedback(form_summary_text, model=None, tokenizer=None):
    """
    Generate LLM feedback from form summary text (optimized for speed)
    
    Args:
        form_summary_text: The text summary from process_frame (e.g., "Body Type: ...")
        model: Pre-loaded model (optional, will load if not provided)
        tokenizer: Pre-loaded tokenizer (optional, will load if not provided)
    
    Returns:
        str: Generated feedback text, or None if model not available
    """
    if model is None or tokenizer is None:
        model, tokenizer = load_llm_model()
    
    if model is None or tokenizer is None:
        return None
    
    instruction = "You are an expert fitness trainer and biomechanics specialist on back squat. Analyze back squat form data. Provide corrective feedback considering form issues, body type, and measurements. Give actionable recommendations."
    
    prompt = format_prompt(instruction, form_summary_text)
    
    try:
        inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
        
        with torch.no_grad():
            # Faster generation settings for speed
            outputs = model.generate(
                **inputs,
                max_new_tokens=256,  # Increased to allow complete responses
                temperature=0.3,  # Lower = faster, more deterministic
                top_p=0.8,  # Lower = faster
                do_sample=False,  # Greedy decoding = faster
                pad_token_id=tokenizer.eos_token_id,
                eos_token_id=tokenizer.eos_token_id,  # Explicitly set EOS token
                use_cache=True,  # Enable KV cache
                num_beams=1,  # No beam search = faster
            )
        
        # Decode only the new tokens (response part)
        input_length = inputs.input_ids.shape[1]
        response = tokenizer.decode(outputs[0][input_length:], skip_special_tokens=True)
        
        # Clean up any incomplete sentences at the end
        response = response.strip()
        
        # If response ends abruptly, try to find the last complete sentence
        if response and not response.endswith(('.', '!', '?')):
            # Find last complete sentence
            last_period = response.rfind('.')
            last_exclamation = response.rfind('!')
            last_question = response.rfind('?')
            last_sentence_end = max(last_period, last_exclamation, last_question)
            
            if last_sentence_end > len(response) * 0.5:  # Only truncate if we have at least 50% of response
                response = response[:last_sentence_end + 1]
        
        return response
    except Exception as e:
        print(f"Error generating feedback: {e}")
        return None

def generate_feedback_batch(summaries, model=None, tokenizer=None):
    """
    Generate feedback for multiple summaries (can be faster with batching)
    
    Args:
        summaries: List of summary texts
        model: Pre-loaded model (optional)
        tokenizer: Pre-loaded tokenizer (optional)
    
    Returns:
        list: List of feedback strings
    """
    if model is None or tokenizer is None:
        model, tokenizer = load_llm_model()
    
    if model is None or tokenizer is None:
        return [None] * len(summaries)
    
    feedbacks = []
    for summary in summaries:
        feedback = generate_feedback(summary, model, tokenizer)
        feedbacks.append(feedback)
    
    return feedbacks

