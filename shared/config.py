"""Load settings from the project-root .env file.

Real environment variables take precedence over .env values (override=False),
so a variable set in the shell or in the test harness always wins.
"""

from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[1]

load_dotenv(PROJECT_ROOT / ".env", override=False)
