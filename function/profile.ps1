# FillerTimer only calls Invoke-RestMethod against the GitHub API - no Az
# PowerShell module is installed (see requirements.psd1), so this profile
# intentionally does not run the default Connect-AzAccount -Identity block
# that Azure would otherwise auto-generate here on cold start.
