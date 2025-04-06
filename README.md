# Notemd - Advanced Knowledge Processing System

## Overview
Notemd is a comprehensive knowledge management system designed for academic and technical documentation. It provides automated processing of PDF documents into structured Markdown with Obsidian integration, featuring:

- Multi-stage document processing pipeline
- Intelligent knowledge point extraction
- Automated backlink generation for knowledge graphs
- Advanced duplicate detection algorithms
- Multi-LLM provider support (DeepSeek/OpenAI/Anthropic)

## System Components

### PowerShell Scripts
- **Generate-Documentation.ps1**: Core processing engine for individual markdown files
- **Process-PDFPipeline.ps1**: Batch processor with advanced file handling
- **DeleteDuplicates.ps1**: Advanced duplicate detection and cleanup

### Python Modules
- **process.py**: PDF processing core
- **generate.py**: Documentation generation
- **clean.py**: Duplicate detection and cleanup

## Project Structure
```
Notemd-git/
├── Notemd/                  # Core Python package
│   ├── __init__.py          # Package initialization
│   ├── clean.py             # Duplicate detection
│   ├── generate.py          # Documentation generation
│   ├── process.py           # PDF processing core
│   └── scripts/             # PowerShell automation scripts
├── requirements.txt         # Python dependencies
├── setup.py                 # Installation script
├── *.ps1                    # Processing scripts
└── .env.example             # Configuration template
```

## Installation & Setup

### Prerequisites
- **PowerShell 7.2+** (required for advanced scripting)
- **Python 3.10+** (for document processing)
- **LLM API Key** (DeepSeek/OpenAI/Anthropic)
- **Obsidian** (for knowledge graph visualization)

### Step-by-Step Installation
1. Clone repository:
```bash
git clone https://github.com/Jacobinwwey/Notemd.git
cd Notemd
```

2. Create virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows
```

3. Install dependencies:
```bash
pip install -r requirements.txt
pip install -e .
```

4. Configuration:
```bash
cp .env.example .env
# Configure paths and API keys in .env
```

## Core Features

### PDF Processing Pipeline
- Converts PDF to clean Markdown with preserved structure
- Intelligent chunking for large documents (3000 words/chunk)
- Mathematical notation preservation
- Automated header normalization

### Knowledge Extraction
- AI-powered concept identification (DeepSeek/OpenAI)
- Obsidian backlink generation
- Knowledge graph node creation
- Technical terminology handling

### Advanced Script Capabilities
- **Batch Processing**: Automatic retries and timeout handling
- **Error Recovery**: Robust logging and resume capabilities
- **Duplicate Detection**: Symbol normalization and containment checks
- **Scheduling**: Configurable processing intervals and cycles

## Configuration

### Environment Variables (.env)
```ini
# Required Paths
KNOWLEDGE_BASE_PATH=/path/to/knowledge_base
SEARCH_PATH=/path/to/search/files

# LLM Configuration
LLM_PROVIDER=deepseek
DEEPSEEK_API_KEY=your_api_key
DEEPSEEK_MODEL=deepseek-reasoner

# Processing Parameters
CHUNK_SIZE=3000          # Words per processing chunk
TEMPERATURE=0.5          # AI response creativity (0.0-1.0)
MAX_TOKENS=8192          # Maximum tokens per request

# Scheduling (Process-PDFPipeline.ps1)
START_DELAY_HOURS=0.000001
TIMEOUT_HOURS=8
CHECK_INTERVAL=30
MAX_CYCLES=1000
```

## Usage Examples

### Single File Processing
```bash
notemd-process research_paper.pdf --output-dir ./knowledge_base
```

### Batch Processing
```powershell
.\Process-PDFPipeline.ps1 -InputDir ./papers -OutputDir ./knowledge
```

### Documentation Generation
```bash
notemd-generate --model deepseek-reasoner --temperature 0.7
```

### Obsidian Integration
1. Open Obsidian and create/open a vault
2. Add the knowledge base directory to your vault
3. Navigate the automatically generated knowledge graph

## Advanced Configuration

### Customizing AI Prompts
Edit the `$structuredPrompt` variable in scripts to modify concept identification.

### Extending LLM Support
1. Add new provider in Process-PDFPipeline.ps1
2. Implement API calls in generate.py
3. Update configuration system

## Troubleshooting

### Common Issues
1. **API Timeouts**: Increase timeout values in configuration
2. **Encoding Errors**: Ensure UTF-8 file handling
3. **Missing Backlinks**: Verify content contains identifiable concepts
4. **Duplicate Detection**: Adjust similarity thresholds in clean.py

### Log Files
- processing_errors.log - Detailed error information
- processed.log - Completed file records

## Development

### Building from Source
```bash
python setup.py sdist bdist_wheel
```

### Testing
```bash
python -m pytest tests/
```

## License
MIT License - See LICENSE for details

## Roadmap
- [ ] Multi-language support
- [ ] Enhanced mathematical processing
- [ ] Plugin architecture
- [ ] Web interface
- [ ] Mobile app integration
