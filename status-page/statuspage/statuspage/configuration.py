"""
Django Configuration for Status-Page
Production-ready configuration that reads secrets from AWS Secrets Store CSI driver
with fallback to environment variables for local development.
"""

import os

# ============================================================================
# Secret Retrieval Helper
# ============================================================================

def get_secret(secret_name, default_value=None):
    """
    Read a secret from the AWS Secrets Store CSI driver mounted volume.
    Attempts to read from /mnt/secrets-store/<secret_name> first.
    Falls back to os.getenv for local development and if file not found.
    
    Args:
        secret_name: The name of the secret file to read
        default_value: Default value if secret cannot be read
        
    Returns:
        The secret value (with whitespace stripped) or default_value
    """
    secret_path = f'/mnt/secrets-store/{secret_name}'
    
    try:
        with open(secret_path, 'r') as f:
            return f.read().strip()
    except (FileNotFoundError, IOError):
        # Fallback to environment variable for local development
        return os.getenv(secret_name, default_value)


# ============================================================================
# Required Settings
# ============================================================================

# Allowed hosts - comma-separated or space-separated
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost').split(',')
ALLOWED_HOSTS = [host.strip() for host in ALLOWED_HOSTS]

# PostgreSQL database configuration
DATABASE = {
    'NAME': os.getenv('DB_NAME', 'statuspage'),
    'USER': get_secret('DB_USER', os.getenv('DB_USER', '')),
    'PASSWORD': get_secret('DB_PASSWORD', os.getenv('DB_PASSWORD', '')),
    'HOST': os.getenv('DB_HOST', 'localhost'),
    'PORT': os.getenv('DB_PORT', '5432'),
    'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '300')),
}

# Redis configuration for tasks and caching
REDIS = {
    'tasks': {
        'HOST': os.getenv('REDIS_HOST', 'localhost'),
        'PORT': int(os.getenv('REDIS_PORT', '6379')),
        'PASSWORD': get_secret('REDIS_PASSWORD', os.getenv('REDIS_PASSWORD', '')),
        'DATABASE': int(os.getenv('REDIS_DB_TASKS', '0')),
        'SSL': os.getenv('REDIS_SSL', 'False').lower() == 'true',
    },
    'caching': {
        'HOST': os.getenv('REDIS_HOST', 'localhost'),
        'PORT': int(os.getenv('REDIS_PORT', '6379')),
        'PASSWORD': get_secret('REDIS_PASSWORD', os.getenv('REDIS_PASSWORD', '')),
        'DATABASE': int(os.getenv('REDIS_DB_CACHE', '1')),
        'SSL': os.getenv('REDIS_SSL', 'False').lower() == 'true',
    }
}

# Site URL (used in emails, links, etc.)
SITE_URL = os.getenv('SITE_URL', 'http://localhost:8000')

# Django secret key - CRITICAL: must be read from secrets
SECRET_KEY = get_secret('DJANGO_SECRET_KEY', '')
if not SECRET_KEY:
    raise ValueError('DJANGO_SECRET_KEY secret/env var must be set')


# ============================================================================
# Optional Settings
# ============================================================================

# Administrator email notifications
ADMINS = []
ADMINS_EMAILS = os.getenv('ADMINS_EMAILS', '')
if ADMINS_EMAILS:
    # Format: "John Doe:jdoe@example.com,Jane Smith:jane@example.com"
    for admin_entry in ADMINS_EMAILS.split(','):
        admin_entry = admin_entry.strip()
        if ':' in admin_entry:
            name, email = admin_entry.split(':', 1)
            ADMINS.append((name.strip(), email.strip()))

# Authentication password validators
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
        'OPTIONS': {
            'min_length': int(os.getenv('PASSWORD_MIN_LENGTH', '8')),
        }
    },
]

# Base path for the application
BASE_PATH = os.getenv('BASE_PATH', '')

# CORS settings
CORS_ORIGIN_ALLOW_ALL = os.getenv('CORS_ORIGIN_ALLOW_ALL', 'False').lower() == 'true'
CORS_ORIGIN_WHITELIST = []
cors_whitelist = os.getenv('CORS_ORIGIN_WHITELIST', '')
if cors_whitelist:
    CORS_ORIGIN_WHITELIST = [origin.strip() for origin in cors_whitelist.split(',')]

# Debug mode - should NEVER be True in production
DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'

# Email configuration
EMAIL = {
    'SERVER': os.getenv('EMAIL_HOST', 'localhost'),
    'PORT': int(os.getenv('EMAIL_PORT', '25')),
    'USERNAME': get_secret('EMAIL_USERNAME', os.getenv('EMAIL_USERNAME', '')),
    'PASSWORD': get_secret('EMAIL_PASSWORD', os.getenv('EMAIL_PASSWORD', '')),
    'USE_SSL': os.getenv('EMAIL_USE_SSL', 'False').lower() == 'true',
    'USE_TLS': os.getenv('EMAIL_USE_TLS', 'False').lower() == 'true',
    'TIMEOUT': int(os.getenv('EMAIL_TIMEOUT', '10')),
    'FROM_EMAIL': os.getenv('EMAIL_FROM', 'noreply@example.com'),
}

# Internal IPs for debugging toolbar
INTERNAL_IPS = tuple(
    ip.strip() for ip in os.getenv('INTERNAL_IPS', '127.0.0.1,::1').split(',')
)

# Logging configuration (empty dict = use Django defaults)
LOGGING = {}

# Session and login timeouts
LOGIN_TIMEOUT = int(os.getenv('LOGIN_TIMEOUT', '1209600'))  # 14 days in seconds
SESSION_COOKIE_AGE = int(os.getenv('SESSION_COOKIE_AGE', '1209600'))  # 14 days

# Media root (where uploaded files are stored)
MEDIA_ROOT = os.getenv('MEDIA_ROOT', '')

# Field choices overrides
FIELD_CHOICES = {}

# Enabled plugins
PLUGINS = []
plugins_env = os.getenv('PLUGINS', '')
if plugins_env:
    PLUGINS = [plugin.strip() for plugin in plugins_env.split(',')]

# Plugin configuration
PLUGINS_CONFIG = {
    'sp_uptimerobot': {
        'uptime_robot_api_key': get_secret('UPTIMEROBOT_API_KEY', os.getenv('UPTIMEROBOT_API_KEY', '')),
    },
}

# Background task timeout
RQ_DEFAULT_TIMEOUT = int(os.getenv('RQ_DEFAULT_TIMEOUT', '300'))

# Cookie names
CSRF_COOKIE_NAME = os.getenv('CSRF_COOKIE_NAME', 'csrftoken')
SESSION_COOKIE_NAME = os.getenv('SESSION_COOKIE_NAME', 'sessionid')

# Timezone
TIME_ZONE = os.getenv('TIME_ZONE', 'UTC')

# Date/time formatting
DATE_FORMAT = os.getenv('DATE_FORMAT', 'N j, Y')
SHORT_DATE_FORMAT = os.getenv('SHORT_DATE_FORMAT', 'Y-m-d')
TIME_FORMAT = os.getenv('TIME_FORMAT', 'g:i a')
SHORT_TIME_FORMAT = os.getenv('SHORT_TIME_FORMAT', 'H:i:s')
DATETIME_FORMAT = os.getenv('DATETIME_FORMAT', 'N j, Y g:i a')
SHORT_DATETIME_FORMAT = os.getenv('SHORT_DATETIME_FORMAT', 'Y-m-d H:i')
