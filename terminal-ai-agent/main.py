import typer
from rich.console import Console
from rich.markdown import Markdown
from agent import run_agent, flush_traces

app = typer.Typer(help="Autonomous Terminal AI Assistant")
console = Console()

@app.command()
def chat():
    """Start an interactive chat session with the AI assistant."""
    console.print("\n[bold green]Terminal AI Assistant Initialized (smolagents + Offline Local LLM).[/bold green]")
    console.print("Operating in secure terminal environment. Type 'exit' to stop.\n")
    
    try:
        while True:
            user_input = typer.prompt("You")
            if user_input.lower() in ["exit", "quit", "q"]:
                console.print("[yellow]Shutting down assistant. Goodbye![/yellow]")
                break
            
            with console.status("[bold cyan]Analyzing and acting...[/bold cyan]"):
                try:
                    response = run_agent(user_input)
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    response = f"**Error:** {str(e)}\n\n*Make sure Ollama is running and gemma:2b model is pulled.*"
            
            console.print("\n[bold blue]Assistant:[/bold blue]")
            console.print(Markdown(response))
            console.print()
    finally:
        # Best Practice: Always flush traces on shutdown
        flush_traces()

if __name__ == "__main__":
    app()
