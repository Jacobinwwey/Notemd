# PDF Processing and Knowledge Graph Integration System

I'll create a comprehensive README.md file for your project and suggest an appropriate .gitignore file.

## README.md


# PDF Processing and Knowledge Graph Integration System

A comprehensive PowerShell-based system for processing PDF-derived markdown files and integrating them into an Obsidian knowledge graph with intelligent concept linking.

## Overview

This system provides an automated pipeline for:

1. Processing markdown files extracted from PDFs
2. Identifying and tagging core knowledge concepts with Obsidian backlinks
3. Creating a structured knowledge graph from scientific/technical content
4. Handling large batches of files with intelligent timeout management

## Components

The system consists of two main PowerShell scripts:

- **Generate-Documentation.ps1**: Core processing engine for individual markdown files
- **Process-PDFPipeline.ps1**: Batch processor with advanced file handling capabilities

## Features

- **Intelligent Concept Tagging**: Automatically identifies and tags core concepts with Obsidian backlinks
- **Content Preservation**: Maintains original document structure and formatting
- **Batch Processing**: Handles large document collections with intelligent chunking
- **Timeout Management**: Sophisticated scheduling with automatic resumption
- **Duplicate Detection**: Eliminates redundant knowledge nodes
- **Error Handling**: Robust error recovery and logging

## Requirements

- **PowerShell 7.2+** (required for advanced threading and JSON handling)
- **Python 3.10+** (for document chunking)
- **Obsidian** (for knowledge graph visualization)
- **DeepSeek API Key** (for AI-powered concept identification)

## Installation

1. Clone this repository to your local machine
2. Ensure PowerShell 7.2+ is installed
3. Ensure Python 3.10+ is installed and accessible via PATH
4. Set up your DeepSeek API key (see Configuration section)
5. Create an Obsidian vault or identify an existing one for knowledge integration

## Configuration

### API Key Setup

Set your DeepSeek API key as an environment variable:

```powershell
$env:DEEPSEEK_API_KEY = 'your-api-key-here'
```

For persistent storage, add this to your PowerShell profile.

### Directory Structure

The system expects the following directory structure:

```
/
├── Process-PDFPipeline.ps1
├── Generate-Documentation.ps1
├── Knowledge/              # Knowledge base for Obsidian nodes
└── [Your markdown files]   # Files to process (*.md)
```

### Configuration Parameters

Both scripts contain configuration sections that can be modified:

#### Generate-Documentation.ps1

```powershell
$DEEPSEEK_CONFIG = @{
    Model           = "deepseek-reasoner"  # AI model to use
    Temperature     = 0.5                  # Response creativity (0.0-1.0)
    MaxTokens       = 8192                 # Maximum response length
    # Additional parameters...
}
```

#### Process-PDFPipeline.ps1

```powershell
$config = @{
    ProcessSuffix   = "_process"           # Suffix for processing directories
    KnowledgeBase   = ".\Knowledge"        # Path to knowledge base
    ChunkSize       = 3000                 # Words per chunk for processing
    # Additional parameters...
}

$SCHEDULE_CONFIG = @{
    StartDelayHours = 3                    # Initial processing delay
    TimeoutHours    = 8                    # Hours before timeout
    # Additional parameters...
}
```

## Usage

### Basic Processing

To process all markdown files in the current directory:

```powershell
.\Generate-Documentation.ps1
```

### Batch Processing

To process all `full.md` files in the current directory and subdirectories:

```powershell
.\Process-PDFPipeline.ps1
```

### Obsidian Integration

1. Open Obsidian
2. Create or open a vault
3. Add the `Knowledge` directory as a folder in your vault
4. Navigate the automatically generated knowledge graph

## Processing Flow

1. **File Discovery**: System scans for markdown files to process
2. **Validation**: Files are checked for valid headers and content
3. **Chunking** (batch mode): Large files are split into manageable chunks
4. **AI Processing**: DeepSeek API identifies core concepts
5. **Backlink Insertion**: Core concepts are wrapped in Obsidian backlinks
6. **Knowledge Node Creation**: Empty files are created for each concept
7. **Deduplication**: Redundant concept files are eliminated

## Troubleshooting

### Common Issues

- **API Connection Failures**: Verify your API key and internet connection
- **Processing Timeouts**: Increase timeout values in configuration
- **Missing Backlinks**: Check that your content contains identifiable concepts

### Logs

- **Processing Errors**: Check `processing_errors.log` for detailed error information
- **Processed Files**: Review `processed.log` to see which files have been completed

## Advanced Usage

### Customizing Prompts

To modify how concepts are identified, edit the `$structuredPrompt` variable in the `Invoke-DeepseekRequest` function.

### Scheduling

The batch processor includes sophisticated scheduling capabilities:

```powershell
$SCHEDULE_CONFIG = @{
    StartDelayHours = 3      # Delay processing start
    TimeoutHours    = 8      # Hours before timeout
    CheckInterval   = 30     # Seconds between checks
    MaxCycles       = 1000   # Maximum processing cycles
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
