#!/bin/bash

# LLM Configuration Setup Script
# This script generates litellm-config.yaml based on available API keys in .env

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
CONFIG_FILE="${SCRIPT_DIR}/litellm-config.yaml"

# ============================================================================
# MODEL DICTIONARY - Categorized by Provider and Complexity
# ============================================================================

# Function to get model name given provider and complexity
get_model() {
    local provider=$1
    local complexity=$2
    
    case "${provider}_${complexity}" in
        openai_simple)      echo "gpt-5-nano" ;;
        openai_medium)      echo "gpt-5-mini" ;;
        openai_reasoning)   echo "gpt-5.3-codex" ;;
        openai_complex)     echo "gpt-5.4" ;;
        
        google_simple)      echo "gemini-3.1-flash-lite" ;;
        google_medium)      echo "gemini-3-flash" ;;
        google_reasoning)   echo "gemini-3.1-pro" ;;
        google_complex)     echo "gemini-3.1-pro" ;;
        
        anthropic_simple)   echo "claude-haiku-4.5" ;;
        anthropic_medium)   echo "claude-sonnet-4.6" ;;
        anthropic_reasoning) echo "claude-opus-4.6" ;;
        anthropic_complex)  echo "claude-opus-4.6" ;;
        
        openrouter_simple)  echo "openai/gpt-5-nano" ;;
        openrouter_medium)  echo "openai/gpt-5-mini" ;;
        openrouter_reasoning) echo "openai/gpt-5.3-codex" ;;
        openrouter_complex) echo "openai/gpt-5.4" ;;
        
        *) echo "" ;;
    esac
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Load environment variables from .env file
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        echo -e "${GREEN}✓${NC} Loaded .env file"
    else
        echo -e "${YELLOW}⚠${NC} .env file not found at $ENV_FILE"
    fi
}

# Check if an environment variable is set and not empty
has_api_key() {
    local key_name=$1
    if [ -z "${!key_name}" ]; then
        return 1
    fi
    return 0
}

# Generate a model entry in YAML format
generate_model_entry() {
    local model_name=$1
    local provider=$2
    local complexity=$3
    local api_key_var=$4
    local model_value=$5
    
    # For OpenRouter, model_value already includes the provider prefix (e.g., "openai/gpt-5-nano")
    # so we don't prepend the provider name again
    local full_model_name
    if [ "$provider" = "openrouter" ]; then
        full_model_name="${model_value}"
    else
        full_model_name="${provider}/${model_value}"
    fi
    
    cat << EOF

  - model_name: ${complexity}
    litellm_params:
      model: ${full_model_name}
      api_key: "os.environ/${api_key_var}"
EOF

    # Add provider-specific configurations
    case $provider in
        google)
            cat << EOF
      extra_headers:
        "x-goog-api-client": "gl-python/litellm"
EOF
            ;;
        anthropic)
            # Anthropic doesn't need extra config
            ;;
        openai)
            # OpenAI doesn't need extra config
            ;;
        openrouter)
            cat << EOF
      api_base: "https://openrouter.ai/api/v1"
      custom_llm_provider: "openai"
      extra_headers:
        "HTTP-Referer": "http://localhost:4000"
        "X-Title": "LiteLLM-Docker"
EOF
            ;;
    esac
}

# Generate OpenAI models section
generate_openai_section() {
    if ! has_api_key "OPENAI_API_KEY"; then
        return
    fi
    
    echo -e "${GREEN}✓${NC} OpenAI API key found" >&2
    
    for complexity in simple medium reasoning complex; do
        local model=$(get_model "openai" "${complexity}")
        generate_model_entry "openai-${complexity}" "openai" "${complexity}" "OPENAI_API_KEY" "${model}"
    done
}

# Generate Google models section
generate_google_section() {
    if ! has_api_key "GOOGLE_API_KEY"; then
        return
    fi
    
    echo -e "${GREEN}✓${NC} Google API key found" >&2
    
    for complexity in simple medium reasoning complex; do
        local model=$(get_model "google" "${complexity}")
        generate_model_entry "google-${complexity}" "google" "${complexity}" "GOOGLE_API_KEY" "${model}"
    done
}

# Generate Anthropic models section
generate_anthropic_section() {
    if ! has_api_key "ANTHROPIC_API_KEY"; then
        return
    fi
    
    echo -e "${GREEN}✓${NC} Anthropic API key found" >&2
    
    for complexity in simple medium reasoning complex; do
        local model=$(get_model "anthropic" "${complexity}")
        generate_model_entry "anthropic-${complexity}" "anthropic" "${complexity}" "ANTHROPIC_API_KEY" "${model}"
    done
}

# Generate OpenRouter models section
generate_openrouter_section() {
    if ! has_api_key "OPENROUTER_API_KEY"; then
        return
    fi
    
    echo -e "${GREEN}✓${NC} OpenRouter API key found" >&2
    
    for complexity in simple medium reasoning complex; do
        local model=$(get_model "openrouter" "${complexity}")
        generate_model_entry "openrouter-${complexity}" "openrouter" "${complexity}" "OPENROUTER_API_KEY" "${model}"
    done
}

# Generate the complexity router section
generate_complexity_router() {
    cat << 'EOF'

  - model_name: openclaw-smart-router
    litellm_params:
      model: auto_router/complexity_router
      complexity_router_config:
        tiers:
          SIMPLE: simple
          MEDIUM: medium
          REASONING: reasoning
          COMPLEX: complex
        
        tier_boundaries:
          simple_medium: 0.15
          medium_complex: 0.35
          complex_reasoning: 0.60
        
        # Token count thresholds
        token_thresholds:
          simple: 15    # Below this = "short" (default: 15)
          complex: 400  # Above this = "long" (default: 400)
        
        # Dimension weights (must sum to ~1.0)
        dimension_weights:
          tokenCount: 0.10
          codePresence: 0.3
          reasoningMarkers: 0.25
          technicalTerms: 0.25
          simpleIndicators: 0.05
          multiStepPatterns: 0.03
          questionComplexity: 0.02
        
        # Override default keyword lists
        code_keywords:
          - function
          - class
          - def
          - async
          - database
          - refactor
          - unit test
          - boilerplate
          - algorithm
          - optimization
        
        reasoning_keywords:
          - step by step
          - từng bước
          - think through
          - suy nghĩ
          - analyze
          - phân tích
          - evaluate
          - đánh giá
          - compare
          - so sánh
          - reasoning
          - lập luận
          - logic
          - inference
          - suy luận
          - multi-step
          - đa bước
          - lập kế hoạch
          - roadmap
          - kiến trúc
          - system design
          - tại sao code này không chạy
          
      # Fallback model if tier cannot be determined
      complexity_router_default_model: simple

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"

litellm_settings:
  drop_params: True
EOF
}

# Generate the complete configuration file
generate_config() {
    local temp_file="${CONFIG_FILE}.tmp"
    
    {
        echo "model_list:"
        generate_openai_section
        generate_google_section
        generate_anthropic_section
        generate_openrouter_section
        generate_complexity_router
    } > "$temp_file"
    
    mv "$temp_file" "$CONFIG_FILE"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${YELLOW}=== LiteLLM Configuration Setup ===${NC}\n"
    
    # Load environment variables
    load_env
    echo ""
    
    # Check which API keys are available
    echo -e "${YELLOW}Checking for API keys...${NC}"
    local has_any_key=false
    
    if has_api_key "OPENAI_API_KEY"; then
        echo -e "${GREEN}✓${NC} OPENAI_API_KEY is set"
        has_any_key=true
    fi
    
    if has_api_key "GOOGLE_API_KEY"; then
        echo -e "${GREEN}✓${NC} GOOGLE_API_KEY is set"
        has_any_key=true
    fi
    
    if has_api_key "ANTHROPIC_API_KEY"; then
        echo -e "${GREEN}✓${NC} ANTHROPIC_API_KEY is set"
        has_any_key=true
    fi
    
    if has_api_key "OPENROUTER_API_KEY"; then
        echo -e "${GREEN}✓${NC} OPENROUTER_API_KEY is set"
        has_any_key=true
    fi
    
    if [ "$has_any_key" = false ]; then
        echo -e "${RED}✗${NC} No API keys found in .env"
        echo ""
        echo -e "${RED}Error: Please configure at least one LLM provider API key before proceeding.${NC}"
        echo ""
        echo -e "${YELLOW}How to set up API keys:${NC}"
        echo ""
        echo "1. Create or edit your .env file at: $ENV_FILE"
        echo ""
        echo "2. Add at least one of the following API keys:"
        echo ""
        echo "   ${GREEN}OpenAI:${NC}"
        echo "     - Get your key from: https://platform.openai.com/api-keys"
        echo "     - Add to .env: OPENAI_API_KEY=sk-..."
        echo ""
        echo "   ${GREEN}Google (Gemini):${NC}"
        echo "     - Get your key from: https://ai.google.dev/"
        echo "     - Add to .env: GOOGLE_API_KEY=..."
        echo ""
        echo "   ${GREEN}Anthropic (Claude):${NC}"
        echo "     - Get your key from: https://console.anthropic.com/account/keys"
        echo "     - Add to .env: ANTHROPIC_API_KEY=sk-ant-..."
        echo ""
        echo "   ${GREEN}OpenRouter:${NC}"
        echo "     - Get your key from: https://openrouter.ai/keys"
        echo "     - Add to .env: OPENROUTER_API_KEY=sk-or-..."
        echo ""
        echo "3. Example .env format:"
        echo "   ${YELLOW}OPENAI_API_KEY=sk-your-key-here${NC}"
        echo "   ${YELLOW}GOOGLE_API_KEY=your-google-api-key${NC}"
        echo ""
        echo "4. After adding keys, run this script again:"
        echo "   ${YELLOW}./llm-setup.sh${NC}"
        echo ""
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}Generating litellm-config.yaml...${NC}"
    
    # Generate configuration
    generate_config
    
    echo -e "${GREEN}✓${NC} Configuration generated successfully at: $CONFIG_FILE"
    echo ""
    
    # Show the generated file
    if command -v head &> /dev/null; then
        echo -e "${YELLOW}Preview (first 30 lines):${NC}"
        head -30 "$CONFIG_FILE"
        echo ""
        echo -e "${YELLOW}... (use 'cat $CONFIG_FILE' to see full config)${NC}"
    fi
}

# Run main function
main "$@"
