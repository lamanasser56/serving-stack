import time

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig


MODEL_ID = "Qwen/Qwen2.5-1.5B-Instruct"


def load(dtype):
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    if dtype == "fp16":
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID, torch_dtype=torch.float16, device_map="cuda"
        )
    elif dtype == "int8":
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID,
            quantization_config=BitsAndBytesConfig(load_in_8bit=True),
            device_map="cuda",
        )
    elif dtype == "int4":
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID,
            quantization_config=BitsAndBytesConfig(load_in_4bit=True),
            device_map="cuda",
        )
    else:
        raise ValueError(dtype)
    return tok, model


def tokens_per_s(dtype, new_tokens=128):
    tok, model = load(dtype)
    messages = [
        {"role": "user", "content": "Explain what a GPU does, in three sentences."}
    ]
    ids = tok.apply_chat_template(
        messages, add_generation_prompt=True, return_tensors="pt"
    ).to("cuda")
    model.generate(input_ids=ids, max_new_tokens=8)
    torch.cuda.synchronize()
    start = time.time()
    output = model.generate(
        input_ids=ids, max_new_tokens=new_tokens, do_sample=False
    )
    torch.cuda.synchronize()
    elapsed = time.time() - start
    generated = output.shape[1] - ids.shape[1]
    return generated / elapsed


if __name__ == "__main__":
    for precision in ["fp16", "int8", "int4"]:
        print(precision, "%.1f tok/s" % tokens_per_s(precision))
