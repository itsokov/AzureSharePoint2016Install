#region variables

$resourceGroupName="SP2016Dev"
$location="WestEurope"
$sqlBinaryUrl=''
$sharepointBinaryUrl='https://download.microsoft.com/download/0/0/4/004EE264-7043-45BF-99E3-3F74ECAE13E5/officeserver.img'
$tempDownloadLocation='C:\temp'
$storageAccountShareName="assets"
$randSAName= -join ((97..122) | Get-Random -Count 9 | % {[char]$_})
$driveToMap='X:'
$sharepointBinaryLocation="$driveToMap\officeserver.img"
$yourAdminPassword=Read-Host -Prompt "Please enter the password you will use for all accounts"
#$autoSPInstallerScriptsUrl='https://github.com/brianlala/AutoSPInstaller/archive/master.zip'
#endregion



Login-AzureRmAccount
Get-AzureRmSubscription| select -First 1 | Select-AzureRmSubscription

$resourceGroup=New-AzureRmResourceGroup "$resourceGroupName" -Location $location

$storageAcct=New-AzureRmStorageAccount -Name $randSAName -ResourceGroupName $resourceGroupName -SkuName Standard_LRS -Location $location 
$storageAccountShare=New-AzureStorageShare  -Name $storageAccountShareName  -Context $storageAcct.Context 
$storkey = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $randSAName
#$password=ConvertTo-SecureString -String $storkey -AsPlainText -Force
#New-SmbMapping -LocalPath X: -RemotePath "\\$randSAName.file.core.windows.net\$storageAccountShareName" -username "$randSAName" -Password $storkey[0].Value
net use $driveToMap "\\$randSAName.file.core.windows.net\$storageAccountShareName" $storkey[0].Value /user:$randSAName
#New-Item -Path "$driveToMap" -ItemType Directory -Name 'SharePointInstall'
(New-Object System.Net.WebClient).DownloadFile($sharepointBinaryUrl, $sharepointBinaryLocation)


### download SQL image


### download GitHub Scripts and Config and create folder structure
#(New-Object System.Net.WebClient).DownloadFile($autoSPInstallerScriptsUrl, "$driveToMap\autospinstaller.zip")

#new-item -Path "$driveToMap" -ItemType Directory "SP\2016\SharePoint\PrerequisiteInstallerFiles"
#new-item -path "$driveToMap\SP" -ItemType Directory 'AutoSPInstaller'



### edit passwords in autospinstaller config
$xml=Get-Content "$driveToMap\SP\AutoSPInstaller\AutoSPInstallerInput.xml"
$xml=$xml -replace "QD59r3cDZk74pYdYxF87", $yourAdminPassword
Set-Content -Value $xml -Path "$driveToMap\SP\AutoSPInstaller\AutoSPInstallerInput.xml"

### extract sharepoint and SQL images

$mountIso=Mount-DiskImage -ImagePath "$driveToMap\SQLServer2016SP2-FullSlipstream-x64-ENU.iso" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter

Copy-Item -Container "$isoDriveLetter`:" -Destination "$driveToMap\SQLMedia" -Recurse

### John Savill Part