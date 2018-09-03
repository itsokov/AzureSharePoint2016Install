#region variables
$storkey = '<storage account key>'
$sharepointBinaryUrl='https://download.microsoft.com/download/0/0/4/004EE264-7043-45BF-99E3-3F74ECAE13E5/officeserver.img'
$driveToMap='X:'
$sharepointBinaryLocation="$driveToMap\officeserver.img"
$sqlBinaryUrl='https://itsokov.blob.core.windows.net/installblob/SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
$sqlBinaryLocation="$driveToMap\SQLServer2016SP2-FullSlipstream-x64-ENU.iso"
$netbiosname = 'contoso'
$yourAdminPassword="<your admin pass>"

#endregion variables

#Add domain admin called Administrator
New-ADUser -Name 'administrator' -GivenName 'admin' -Surname 'istrator' `
    -SamAccountName 'administrator' -UserPrincipalName "administrator@$netbiosname.local" `
    -AccountPassword (ConvertTo-SecureString -AsPlainText "$yourAdminPassword" -Force) `
    -Enabled $true

Add-ADGroupMember 'Domain Admins' administrator

New-NetFirewallRule -DisplayName "MSSQL ENGINE TCP" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "SharePoint TCP 2013" -Direction Inbound -LocalPort 2013 -Protocol TCP -Action Allow

net use $driveToMap "\\<storage account name>.file.core.windows.net\<SAShareName>" $storkey /user:<storage account name> 

#region copyand edit AutoSPInstaller files

    #this section had to be moved from main script due to the network restrictions in DXC

New-Item -Path c:\ -Name Temp -ItemType Directory

$file = "c:\temp\gitassets.zip"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
(New-Object System.Net.WebClient).DownloadFile($gitHubAssets, "$file")

    # Unzip the file to specified location
$shell_app=new-object -com shell.application 
$zip_file = $shell_app.namespace($file) 
$destination = $shell_app.namespace("c:\temp") 
$destination.Copyhere($zip_file.items())
Copy-Item -Path C:\Temp\AzureSharePoint2016Install-master\* -Destination C:\Temp -confirm:$false -Force -Recurse
Remove-Item  C:\Temp\AzureSharePoint2016Install-master -Force -Confirm:$false -Recurse
Remove-Item $file -Force -Confirm:$false

$xml=Get-Content "C:\temp\SP\AutoSPInstaller\AutoSPInstallerInput.xml"
$xml=$xml -replace "QD59r3cDZk74pYdYxF87", $yourAdminPassword
Set-Content -Value $xml -Path "C:\temp\SP\AutoSPInstaller\AutoSPInstallerInput.xml"
Copy-Item -Path C:\temp\SP -Destination $driveToMap -recurse -Force
Remove-Item C:\Temp -Recurse -Force -Confirm:$false

#endregion


#SharePoint Setup files
New-Item -Path "$driveToMap\" -ItemType Directory -Name 'SharePointInstall'
Start-Job -Name SP_Download -ScriptBlock {(New-Object System.Net.WebClient).DownloadFile($sharepointBinaryUrl, $sharepointBinaryLocation)}

### download SQL image
Start-Job -Name SQL_Download -ScriptBlock {(New-Object System.Net.WebClient).DownloadFile($sqlBinaryUrl, $sqlBinaryLocation)}



#Copy-Item -Recurse -Path X:\AutoSPInstaller -Destination C:\Assets\
#Configuration files that make up SQL and SharePoint install including the SharePoint backup
#Copy-Item -Recurse -Path X:\POCAzureScripts\* -Destination C:\Assets\

#service account creation Install
$AccountsToCreate = @("SP_CacheSuperUser","SP_CacheSuperReader","SP_Services","SP_PortalAppPool","SP_ProfilesAppPool","SP_SearchService","SP_SearchContent","SP_ProfileSync","SP_SQL")

foreach($account in $AccountsToCreate)
{
  New-ADUser -Name $account -GivenName $account -Surname $account `
    -SamAccountName $account -UserPrincipalName "$account@$netbiosname.local" `
    -AccountPassword (ConvertTo-SecureString -AsPlainText "$yourAdminPassword" -Force) `
    -Enabled $true
}

Get-Job | Wait-Job
#SQL Install
$mountIso=Mount-DiskImage -ImagePath "$sqlBinaryLocation" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter

$sqlsysadminaccounts = $env:USERDOMAIN + "\" + $env:USERNAME
$setup = "($isoDriveLetter):\setup.exe"
$command = "cmd /c $setup /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /FEATURES=SQLEngine,ADV_SSMS /INSTANCENAME=MSSQLSERVER /Q /SQLSVCACCOUNT=SP_SQL /SQLSVCPASSWORD=$yourAdminPassword /INDICATEPROGRESS /SQLSYSADMINACCOUNTS=$sqlsysadminaccounts"
Invoke-Expression -Command:$command
Dismount-DiskImage -InputObject $mountIso

#extract SharePoint
$mountIso=Mount-DiskImage -ImagePath "$sharepointBinaryLocation" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter
Copy-Item -Container "$isoDriveLetter`:" -Destination "$driveToMap\SP\2016\SharePoint" -Recurse
Dismount-DiskImage -InputObject $mountIso


#Perform SharePoint install
$SPInstallJob = Start-Job -ScriptBlock {"$driveToMap\SP\AutoSPInstaller\AutoSPInstallerLaunch.bat"}
get-job | Wait-Job
#Remove-SmbMapping *
net use $driveToMap /delete
