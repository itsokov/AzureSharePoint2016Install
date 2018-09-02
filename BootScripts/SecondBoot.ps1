﻿#region variables
$storkey = '<storage account key>'
$sharepointBinaryUrl='https://download.microsoft.com/download/0/0/4/004EE264-7043-45BF-99E3-3F74ECAE13E5/officeserver.img'
$driveToMap='X:'
$sharepointBinaryLocation="$driveToMap\officeserver.img"
$sqlBinaryUrl='https://itsokov.blob.core.windows.net/installblob/SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
$sqlBinaryLocation="$driveToMap\SQLServer2016SP2-FullSlipstream-x64-ENU.iso"

#endregion variables

#Add domain admin called Administrator
New-ADUser -Name 'administrator' -GivenName 'admin' -Surname 'istrator' `
    -SamAccountName 'administrator' -UserPrincipalName 'administrator@pocdom.local' `
    -AccountPassword (ConvertTo-SecureString -AsPlainText 'Pa55word' -Force) `
    -Enabled $true

Add-ADGroupMember 'Domain Admins' administrator

New-NetFirewallRule -DisplayName "MSSQL ENGINE TCP" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "SharePoint TCP 2013" -Direction Inbound -LocalPort 2013 -Protocol TCP -Action Allow


New-SmbMapping -LocalPath $driveToMap -RemotePath \\<storage account name>.file.core.windows.net\<SAShareName> -username '<storage account name>' -Password $storkey

#SharePoint Setup files
New-Item -Path "$driveToMap" -ItemType Directory -Name 'SharePointInstall'
(New-Object System.Net.WebClient).DownloadFile($sharepointBinaryUrl, $sharepointBinaryLocation)

### download SQL image
(New-Object System.Net.WebClient).DownloadFile($sqlBinaryUrl, $sharepointBinaryLocation)

Copy-Item -Recurse -Path X:\AutoSPInstaller -Destination C:\Assets\
#Configuration files that make up SQL and SharePoint install including the SharePoint backup
Copy-Item -Recurse -Path X:\POCAzureScripts\* -Destination C:\Assets\

#SQL Install
.'X:\SQLServer2012SP3\Setup.exe' /ConfigurationFile="C:\Assets\ConfigurationFile.ini"

Remove-SmbMapping -LocalPath X: -Force

#SharePoint Install
$AccountsToCreate = @("SP_CacheSuperUser","SP_CacheSuperReader","SP_Services","SP_PortalAppPool","SP_ProfilesAppPool","SP_SearchService","SP_SearchContent","SP_ProfileSync")

foreach($account in $AccountsToCreate)
{
  New-ADUser -Name $account -GivenName $account -Surname $account `
    -SamAccountName $account -UserPrincipalName $account@pocdom.local `
    -AccountPassword (ConvertTo-SecureString -AsPlainText 'Pa55word' -Force) `
    -Enabled $true
}

#Perform the actual install
$SPInstallJob = Start-Job -ScriptBlock {C:\Assets\SP\AutoSPInstaller\AutoSPInstallerLaunch.bat}
Start-Sleep -Seconds 2400 #wait for 40 minutes for above to complete