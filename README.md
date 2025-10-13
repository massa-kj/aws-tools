# AWS Tools

Scripts and cheat sheets for my AWS work.
A unified command-line interface for managing multiple AWS services with a clean, modular architecture.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
  - [Basic Usage](#basic-usage)
  - [Common Operations](#common-operations)
- [Architecture](#architecture)
  - [Project Structure](#project-structure)
  - [Configuration Management](#configuration-management)
  - [Layer Architecture](#layer-architecture)
  - [Common Utilities](#common-utilities)
- [Available Services & Global Commands](#available-services--global-commands)
  - [Services](#services)
  - [Global Commands](#global-commands)
- [Development](#development)
  - [Adding a New Service](#adding-a-new-service)
  - [Adding a Global Command](#adding-a-global-command)
- [License](#license)
- [Related](#related)

## Features

- **Unified CLI**: Single entry point (`awstools.sh`) for all AWS operations
- **Modular Architecture**: Clean separation between services and layers
- **Dynamic Service Discovery**: Automatic detection of available services
- **Global Commands**: Cross-service utilities like authentication detection
- **Flexible Configuration**: Profile and region override support
- **Comprehensive Logging**: Debug-friendly logging with color support
- **Extensible Design**: Easy to add new services and commands

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/massa-kj/aws-tools.git
   cd aws-tools
   ```

2. Make the main script executable:
   ```bash
   chmod +x awstools.sh
   ```

3. Ensure AWS CLI v2+ is installed and configured:
   ```bash
   aws --version
   aws configure list
   ```

## Quick Start

### Basic Usage
```bash
# Show help and available services
./awstools.sh --help

# Detect current authentication method
./awstools.sh detect-auth

# List EC2 instances
./awstools.sh ec2 list

# Get help for a specific service
./awstools.sh ec2 help
```

### Common Operations
```bash
# EC2 Management
./awstools.sh ec2 list
./awstools.sh ec2 start i-1234567890abcdef0
./awstools.sh ec2 stop i-1234567890abcdef0
./awstools.sh ec2 describe i-1234567890abcdef0

# QuickSight Management
./awstools.sh quicksight list
./awstools.sh quicksight backup --analysis-id abc123

# Profile Management (NEW)
# Initialize user configuration
./scripts/init-user-config.sh

# Use profile override at runtime
./awstools.sh --profile production ec2 list

# Profile and Region Override
./awstools.sh ec2 list --profile production --region us-west-2
```

## Architecture

### Project Structure
```
aws-tools/
├── awstools.sh               # Main entry point
├── config/                   # Configuration files
│   ├── aws-exec.env          # AWS execution environment settings
│   └── default/              # Default configuration files
├── scripts/                  # Scripts
│   └── init-user-config.sh   # Initialize user configuration
├── commands/                 # Global commands
│   └── {command}.sh          # Individual command scripts (help, version, detect-auth)
├── common/                   # Shared utilities
│   ├── config-loader.sh      # Configuration loader
│   ├── discovery.sh          # Service and command discovery utilities
│   ├── logger.sh             # Logging system
│   └── utils.sh              # AWS execution and common functions
└── services/                 # Service implementations
    └── {service}/            # Individual service (e.g., ec2, quicksight, auth...)
        ├── manifest.sh       # Service metadata
        ├── lib.sh            # Service utilities
        ├── api.sh            # AWS API wrappers
        ├── ui.sh             # Command interface
        └── ...               # Additional service files
```

### Configuration Management

#### User Profile Configuration

AWS Tools now supports user-specific profile configurations stored outside the repository:

##### Initial Setup
```bash
# Initialize user configuration
./scripts/init-user-config.sh

# This creates:
# ~/.config/awstools/config - User configuration file
```

##### User Configuration File Structure
```bash
# ~/.config/awstools/config
AWSTOOLS_PROFILE="default"                    # Default profile to use
AWSTOOLS_PROFILE_DIR="/path/to/profiles"      # Directory containing profile configurations
```

##### Profile Directory Structure
```
/path/to/profiles/
├── dev/                          # Development profile
│   ├── common.env               # Common development settings
│   ├── services/
│   │   ├── ec2.env             # EC2-specific dev settings
│   │   └── rds.env             # RDS-specific dev settings
│   └── custom.env              # Any additional .env files
├── staging/                     # Staging profile
│   ├── common.env
│   └── services/
│       └── ec2.env
└── prod/                        # Production profile
    ├── common.env
    ├── security.env            # Security-specific settings
    └── services/
        ├── ec2.env
        └── quicksight.env
```

##### Profile Loading Behavior
1. **Default Configuration**: Always loaded first as fallback (`config/default/`)
2. **Repository Overrides**: Loaded second (`config/overwrite/`)
3. **User Profile**: Loaded last with highest priority
   - All `.env` files in the profile directory are loaded recursively
   - Files are loaded in alphabetical order for consistency

##### Profile Selection Priority
1. **Command Line**: `--profile` option (highest priority)
2. **User Config**: `AWSTOOLS_PROFILE` in `~/.config/awstools/config`
3. **Fallback**: `"default"` profile

##### Usage Examples
```bash
# Use default profile from user config
./awstools.sh ec2 list

# Override profile at runtime
./awstools.sh --profile prod ec2 list

# Initialize user configuration
./scripts/init-user-config.sh
```

#### Configuration Priority
Configuration values are determined by the following priority order (higher priority wins):

1. **CLI Options** - Runtime specification (highest priority)
   - `--profile`, `--region`, `--config`, `--auth`
   - Dynamic configuration via `--set KEY=VALUE`
2. **Environment Variables** - Shell environment settings (TODO: Not supported yet)
   - `AWS_PROFILE`, `AWS_REGION`, etc.
3. **Local Override Settings** - User-specific configuration
4. **Default Settings** - Project standard configuration
   - `config/default/services/{service}.env`
   - `config/default/environments/{environment}.env`
   - `config/default/common.env`

#### Configuration Management Features

##### Validation
```bash
# Validate configuration integrity
./awstools.sh config validate [environment] [service]

# Validation checks:
# - Required configuration values presence
# - Configuration value format validity
# - Conflicting configuration detection
# - AWS credential validity
```

##### Configuration Visualization
```bash
# Display current effective configuration
./awstools.sh config show [environment] [service]

# Show configuration source trace
./awstools.sh config trace [environment] [service]

# Compare configurations between environments
./awstools.sh config diff <env1> <env2>
```

#### Runtime Configuration Control (`aws_exec` functionality)

##### Automatic Configuration Completion
The `aws_exec` function automatically complements and applies configuration at runtime:

```bash
# Automatic region determination (priority order)
# 1. CLI option --region (highest priority)
# 2. Configuration system (default_region)
# 3. AWS_REGION environment variable
# 4. AWS_DEFAULT_REGION environment variable
# 5. Profile's region setting
# 6. EC2 instance metadata
# 7. Default fallback (us-east-1)

# Automatic profile application
# - When AWS_PROFILE is configured
# - Avoids conflicts with environment variable authentication
```

##### Error Handling and Retry Control
```bash
# Configurable parameters
AWS_EXEC_RETRY_COUNT=3          # Number of retry attempts
AWS_EXEC_RETRY_DELAY=2          # Base delay time (seconds)
AWS_EXEC_TIMEOUT=300            # Timeout (seconds)
AWS_EXEC_MAX_OUTPUT_SIZE=1048576 # Maximum output size (bytes)

# Automatically retryable errors
# - Throttling/RequestLimitExceeded (rate limiting)
# - Network/Connection errors
# - ServiceUnavailable/InternalError (temporary service issues)

# Non-retryable errors
# - AccessDenied/UnauthorizedOperation (permission errors)
# - NoCredentialsError/ExpiredToken (authentication errors)
# - User interruption (Ctrl+C)
```

##### Performance Optimization
```bash
# Service-specific rate limits
AWS_QUICKSIGHT_RATE_LIMIT=10    # QuickSight: 10 req/sec
AWS_EC2_RATE_LIMIT=20           # EC2: 20 req/sec
AWS_S3_RATE_LIMIT=100           # S3: 100 req/sec
AWS_DEFAULT_RATE_LIMIT=50       # Others: 50 req/sec

# Runtime optimization
aws_exec_with_rate_limit quicksight list-analyses
```

##### Environment Validation
```bash
# Validate AWS environment integrity
validate_aws_environment [strict_mode]

# Automatic authentication method detection
# - env-vars (environment variables)
# - profile:profile-name (AWS profile)
# - instance-profile (EC2 instance profile)
# - web-identity (Web Identity token)
```

##### Error Analysis and Guidance
Automatically analyzes errors and suggests solutions:
```bash
# Authentication error suggestions
# 1. Run aws configure
# 2. Set environment variables
# 3. Re-login with SSO

# Permission error suggestions
# 1. Check IAM policies
# 2. Verify AWS account
# 3. Contact administrator
```

#### Future Enhancements (Planned)
- **Configuration Format Extension**: Support for TOML/JSON formats
- **Automatic Environment Detection**: Auto-select profiles based on execution environment
- **Configuration Caching**: Prevent duplicate loading and improve performance
- **Authentication Method Extension**: Comprehensive support for AccessKey/SSO/AssumeRole/WebIdentity
- **Configuration Templates**: Generate configuration templates for new environments and services

### Layer Architecture
Each service follows a 3-layer architecture:

| Layer | File | Responsibility |
|-------|------|----------------|
| **UI Layer** | `ui.sh` | Command parsing, user interaction, workflow control |
| **API Layer** | `api.sh` | AWS CLI wrappers, API calls, response processing |
| **Lib Layer** | `lib.sh` | Service-specific utilities, validation, and configuration management |

### Common Utilities
The `common/` directory provides shared functionality across all services:

| File | Purpose |
|------|---------|
| `discovery.sh` | Service and global command discovery, registry management |
| `config-loader.sh` | Hierarchical configuration loading with priority handling |
| `utils.sh` | AWS CLI execution wrapper with retry logic and error handling |
| `logger.sh` | Structured logging with color support and debug levels |

## Available Services & Global Commands

### Services

- [Auth](services/auth/README.md)
- [EC2](services/ec2/README.md)
- [RDS](services/rds/README.md)
- [QuickSight](services/quicksight/README.md)

### Global Commands

| Command | Description |
|---------|-------------|
| version | Show version information |
| help | Show help information |
| detect-auth | Detect current AWS authentication method |

## Development

### Adding a New Service

1. **Create service directory**:
   ```bash
   mkdir -p services/myservice
   ```

2. **Create manifest.sh**:
   ```bash
   # services/myservice/manifest.sh
   SERVICE_NAME="myservice"
   SERVICE_DESC="Manage MyService resources"
   SERVICE_VERSION="1.0.0"
   ```

3. **Implement layers**:
   - `lib.sh`: Configuration and utilities
   - `api.sh`: AWS API wrappers
   - `ui.sh`: Command interface

4. **Test the service**:
   ```bash
   ./awstools.sh myservice help
   ```

### Adding a Global Command

1. **Register in discovery.sh**:
   ```bash
   # common/discovery.sh - Add to GLOBAL_COMMANDS array
   ["my-command"]="Description of my command"
   ```

2. **Create command script**:
   commands/my-command.sh  
   ```bash
   #!/usr/bin/env bash
   #=============================================================
   # my-command.sh - My custom command
   #=============================================================
   
   set -euo pipefail
   
   # Load common utilities
   BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
   source "${BASE_DIR}/common/logger.sh"
   source "${BASE_DIR}/common/discovery.sh"  # If needed
   
   # Implementation here
   echo "My custom command executed"
   ```

3. **Make executable**:
   ```bash
   chmod +x commands/my-command.sh
   ```

4. **Test the command**:
   ```bash
   ./awstools.sh my-command
   ```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [AWS Service Documentation](https://docs.aws.amazon.com/)

---

**Note**: This tool is designed for AWS operations and requires appropriate AWS credentials and permissions.
