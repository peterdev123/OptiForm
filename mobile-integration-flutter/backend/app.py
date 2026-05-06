"""
Stable backend entrypoint for deployment.

This keeps existing behavior from dev_api while providing a consistent module
path for uvicorn/systemd/docker commands.
"""

from dev_api import app

