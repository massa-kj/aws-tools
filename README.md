# AWS Utilities

Scripts and cheat sheets for my AWS work.
A unified command-line interface for managing multiple AWS services with a clean, modular architecture.

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
   git clone https://github.com/massa-kj/aws-utilities.git
   cd aws-utilities
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

# Profile and Region Override
./awstools.sh ec2 list --profile production --region us-west-2
```

## Architecture

### Project Structure
```
aws-utilities/
├── awstools.sh               # Main entry point
├── config/                   # Configuration files
│   ├── aws-exec.env          # AWS execution environment settings
│   ├── default/              # Default configuration files
│   └── overwrite/            # Local override configuration files
├── commands/                 # Global commands
│   └── {command}.sh          # Individual command scripts (help, version, detect-auth)
├── common/                   # Shared utilities
│   ├── config-loader.sh      # Configuration loader
│   ├── discovery.sh          # Service and command discovery utilities
│   ├── logger.sh             # Logging system
│   └── utils.sh              # AWS execution and common functions
└── services/                 # Service implementations
    └── {service}/            # Individual service (e.g., ec2, quicksight, auth)
        ├── manifest.sh       # Service metadata
        ├── lib.sh            # Service utilities
        ├── api.sh            # AWS API wrappers
        ├── ui.sh             # Command interface
        └── ...               # Additional service files
```

### Configuration Management

#### Configuration File Structure
```
config/
├── aws-exec.env              # AWS execution environment settings
├── default/                  # Default configuration
│   ├── common.env           # Common settings
│   ├── environments/        # Environment-specific settings
│   │   ├── default.env     # Development environment settings
│   │   └── prod.env        # Production environment settings
│   └── services/           # Service-specific settings
│       ├── auth.env        # Authentication service settings
│       ├── ec2.env         # EC2 service settings
│       └── quicksight.env  # QuickSight service settings
└── overwrite/              # Local override configuration
    ├── common.env          # Common settings overrides
    ├── environments/       # Environment settings overrides
    └── services/          # Service settings overrides
```

#### Configuration Loading
Each script loads configuration hierarchically through `config-loader.sh`:
```bash
# Basic usage
load_config <environment> [service]

# Validate configuration
validate_config <environment> [service]

# Show effective configuration
show_effective_config [environment] [service]
```

#### Configuration Priority
Configuration values are determined by the following priority order (higher priority wins):

1. **CLI Options** - Runtime specification (highest priority)
   - `--profile`, `--region`, `--config`, `--auth`
   - Dynamic configuration via `--set KEY=VALUE`
2. **Environment Variables** - Shell environment settings (TODO: Not supported yet)
   - `AWS_PROFILE`, `AWS_REGION`, etc.
3. **Local Override Settings** - User-specific configuration
   - `config/overwrite/services/{service}.env`
   - `config/overwrite/environments/{environment}.env`
   - `config/overwrite/common.env`
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

## Available Services

### EC2 Service
Manage EC2 instances with enhanced state checking and validation.

```bash
./awstools.sh ec2 list                    # List all instances
./awstools.sh ec2 start <instance-id>     # Start instance with state validation
./awstools.sh ec2 stop <instance-id>      # Stop instance with confirmation
./awstools.sh ec2 describe <instance-id>  # Show detailed instance info
```

### QuickSight Service
Manage QuickSight resources including analyses and datasets.

```bash
./awstools.sh quicksight list             # List resources
./awstools.sh quicksight backup           # Backup operations
```

## Global Commands

### Authentication Detection
```bash
./awstools.sh detect-auth
# Output examples:
# profile:my-profile    # Using AWS CLI profile
# env-vars              # Using environment variables
# iam-role              # Using IAM role (EC2, Lambda, etc.)
```

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
