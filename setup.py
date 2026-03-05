"""
Universal Project Launcher
Setup script for easy installation
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read README for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text(encoding='utf-8')

setup(
    name="universal-project-launcher",
    version="3.0.0",
    author="Eric de Carvalho",
    author_email="eric@example.com",
    description="Optimize your Claude AI sessions with intelligent context management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/decarvalhoe/universal-project-launcher",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    install_requires=[
        "PyYAML>=6.0",
        "python-dotenv>=1.0.0",
    ],
    extras_require={
        "full": [
            "pystray>=0.19.0",
            "Pillow>=10.0.0",
            "libtmux>=0.20.0",
            "typer>=0.9.0",
            "rich>=13.0.0",
            "httpx>=0.24.0",
        ],
        "dev": [
            "pytest>=7.0",
            "black>=23.0",
            "flake8>=6.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "upl-launcher=launcher:main",
            "upl-context=context_generator:main",
            "upl-add=add_project:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.yaml", "*.md", "*.bat"],
    },
)