import sys
import traceback
from agent import run_agent

try:
    print("Running run_agent...")
    res = run_agent(
        user_input="what files are in my current folder?",
        api_key="1234567890abcde", # Dummy key length at least 10
        history=[]
    )
    print("Success! Result:", res)
except Exception as e:
    print("Caught Exception:", type(e), e)
    traceback.print_exc()
