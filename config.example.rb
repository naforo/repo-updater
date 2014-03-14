# Who is allowed to POST to the hook
ALLOWED_SENDERS = ["localhost", "github.com", "bitbucket.org"]

# Set this to repository URL to clone. See git documentation for values
# you can pass (e.g. you can use file paths too)
# Value "auto" will determine URL from POST payload
REPOSITORY_URL = "auto"
# REPOSITORY_URL = "git@github.com:user/repo.git"

# Set this to true if you will manually 'git clone' and 'git pull'
MANUAL_REFRESH = false

ACCESS_TOKEN = "change-me"

NAFORO_URL = 'http://naforo.com/hooks/client'
