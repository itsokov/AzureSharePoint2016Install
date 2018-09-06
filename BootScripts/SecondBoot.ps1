#region variables
#$storkey = '<storage account key>'
$sharepointBinaryUrl='<sharePoint iso source>'
#$driveToMap='<drive to map>'
$sharepointBinaryLocation="C:\temp\officeserver.img"
$sqlBinaryUrl='<SQL Binary URL>'
$sqlBinaryLocation="C:\temp\SQLServer2016SP2-FullSlipstream-x64-ENU.iso"
$netbiosname = '<your netbios name>'
$yourAdminPassword='<your admin pass>'
#$randSAName='<storage account name>'
#$storageAccountShareName='<SAShareName>'
$gitHubAssets='<GitHub Assets>'
$setupAccount='<Setup Account>'
#endregion variables

New-NetFirewallRule -DisplayName "MSSQL ENGINE TCP" -Direction Inbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "SharePoint TCP 2013" -Direction Inbound -LocalPort 2013 -Protocol TCP -Action Allow

#net use $driveToMap "\\$randSAName.file.core.windows.net\$storageAccountShareName" $storkey /user:<storage account name> 

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
Copy-Item -Path C:\Temp\AzureSharePoint2016Install-master\* -Destination 'C:\Temp' -confirm:$false -Force -Recurse
Remove-Item  C:\Temp\AzureSharePoint2016Install-master -Force -Confirm:$false -Recurse
Remove-Item $file -Force -Confirm:$false

$xml=Get-Content "C:\temp\SP\AutoSPInstaller\AutoSPInstallerInput.xml"
$xml=$xml -replace "QD59r3cDZk74pYdYxF87", $yourAdminPassword
Set-Content -Value $xml -Path "C:\temp\SP\AutoSPInstaller\AutoSPInstallerInput.xml"


#endregion copyand edit AutoSPInstaller files


#SharePoint Setup files
Start-Job -Name SP_Download -ScriptBlock {param($sharepointBinaryUrl,$sharepointBinaryLocation)(New-Object System.Net.WebClient).DownloadFile($sharepointBinaryUrl, $sharepointBinaryLocation)} -ArgumentList $sharepointBinaryUrl,$sharepointBinaryLocation

### download SQL image
Start-Job -Name SQL_Download -ScriptBlock {param($sqlBinaryUrl, $sqlBinaryLocation)(New-Object System.Net.WebClient).DownloadFile($sqlBinaryUrl, $sqlBinaryLocation)} -ArgumentList $sqlBinaryUrl,$sqlBinaryLocation


#service account creation Install
$AccountsToCreate = @("SP_CacheSuperUser","SP_CacheSuperReader","SP_Services","SP_PortalAppPool","SP_ProfilesAppPool","SP_SearchService","SP_SearchContent","SP_ProfileSync","SP_SQL","SP_Farm")

foreach($account in $AccountsToCreate)
{
  New-ADUser -Name $account -GivenName $account -Surname $account `
    -SamAccountName $account -UserPrincipalName "$account@$netbiosname.local" `
    -AccountPassword (ConvertTo-SecureString -AsPlainText "$yourAdminPassword" -Force) `
    -Enabled $true `
    -PasswordNeverExpires $true
}


#SQL Install
Wait-Job -Name SQL_Download
$mountIso=Mount-DiskImage -ImagePath "$sqlBinaryLocation" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter

$setup = "$isoDriveLetter`:\setup.exe"
$command = "cmd /c $setup /ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /FEATURES=SQLEngine /INSTANCENAME=MSSQLSERVER /Q /SQLSVCACCOUNT=$netbiosname\SP_SQL /SQLSVCPASSWORD=$yourAdminPassword /INDICATEPROGRESS /SQLSYSADMINACCOUNTS=$setupAccount"
Invoke-Expression -Command:$command
#."$isoDriveLetter`:\Setup.exe" /ConfigurationFile="C:\Temp\SQL\ConfigurationFile.ini"

Dismount-DiskImage -InputObject $mountIso

#extract SharePoint
Wait-Job -Name SP_Download
$mountIso=Mount-DiskImage -ImagePath "$sharepointBinaryLocation" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter
Copy-Item -Container "$isoDriveLetter`:" -Destination "C:\Temp\SP\2016\SharePoint" -Recurse
Dismount-DiskImage -InputObject $mountIso

$username = "$netbiosname\$setupAccount"
$password = ConvertTo-SecureString -AsPlainText -String "$yourAdminPassword" -Force
$cred = new-object -typename System.Management.Automation.PSCredential `
         -argumentlist $username, $password


#Perform SharePoint install
#$SPInstallJob = Start-Job -ScriptBlock {C:\temp\SP\AutoSPInstaller\AutoSPInstallerLaunch.bat} -Credential $cred
Invoke-Command -ScriptBlock {C:\temp\SP\AutoSPInstaller\AutoSPInstallerLaunch.bat} -Credential $cred -ComputerName $env:COMPUTERNAME
#Start-Sleep -Seconds 2400 #wait for 40 minutes for above to complete

#Remove-Item C:\Temp -Recurse -Force -Confirm:$false #cleanup