#region variables

$resourceGroupName="SP2016Dev"
$location="WestEurope"
$sharepointBinaryUrl='https://download.microsoft.com/download/0/0/4/004EE264-7043-45BF-99E3-3F74ECAE13E5/officeserver.img'
$sqlBinaryUrl='https://itsokov.blob.core.windows.net/installblob/SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
$tempDownloadLocation='C:\temp'
$storageAccountShareName="assets"
$randSAName= -join ((97..122) | Get-Random -Count 9 | % {[char]$_})
$SASKU = 'Premium_LRS'
$driveToMap='X:'
$sharepointBinaryLocation="$driveToMap\officeserver.img"
$sqlBinaryLocation="$driveToMap\SQLServer2016SP2-FullSlipstream-x64-ENU.iso"
$yourAdminPassword=Read-Host -Prompt "Please enter the password you will use for all accounts"
$VirtNetName = 'VNPOC1'
$VMName = -join ((97..122) | Get-Random -Count 9 | % {[char]$_})
$VMSize ="Standard_DS2"
$ServerSKU="2016-Datacenter"
$setupAccount='sp_setup'
$scriptsContainer="scripts"
$firstBootScriptSource=
#$autoSPInstallerScriptsUrl='https://github.com/brianlala/AutoSPInstaller/archive/master.zip'
#endregion



Login-AzureRmAccount
Get-AzureRmSubscription| select -First 1 | Select-AzureRmSubscription
$resourceGroup=New-AzureRmResourceGroup "$resourceGroupName" -Location $location

$storageAcct=New-AzureRmStorageAccount -Name $randSAName -ResourceGroupName $resourceGroupName -SkuName $SASKU -Location $location 
$storageAccountShare=New-AzureStorageShare  -Name $storageAccountShareName  -Context $storageAcct.Context 
Start-Sleep -Seconds 30
$ScriptBlobKey = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $randSAName



#region JohnSavill


filter timestamp {"$(Get-Date -Format G): $_"}

#Create Resources for new deployment
Write-Output "Setting up VM resources and variables" | timestamp


#Get latest image
$AzureImageSku = Get-AzureRmVMImage -Location $location -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus $ServerSKU
$AzureImageSku = $AzureImageSku | Sort-Object Version -Descending #put the newest first which is the highest patched version
$AzureImage = $AzureImageSku[0] #Newest

#Create a Virtual Network
$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name 'StaticSub' -AddressPrefix "10.10.1.0/24"
$vnet = New-AzureRmVirtualNetwork -Force -Name $VirtNetName -ResourceGroupName $resourceGroupName `
    -Location $location -AddressPrefix "10.10.0.0/16" -Subnet $subnet # -DnsServer "10.10.1.10" don't set yet
#If VM points to itself and not offering DNS yet the agents will hang during install

#Create VM
$vm = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
#Create NIC
#For demo for easy access give a public IP
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName -Name ('PubIP' + $VMName) `
    -Location $Location -AllocationMethod Dynamic -DomainNameLabel $vmname.ToLower()
$nic = New-AzureRmNetworkInterface -Force -Name ('nic' + $VMName) -ResourceGroupName $resourceGroupName `
    -Location $Location -SubnetId $vnet.Subnets[0].Id -PrivateIpAddress 10.10.1.10 `
    -PublicIpAddressId $pip.Id
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

$osDiskName = $VMName+'-OSDisk'
$osDiskCaching = 'ReadWrite'
$osDiskVhdUri = "https://$randSAName.blob.core.windows.net/vhds/"+$VMName+"-OS.vhd"

# Setup OS & Image
$user = $setupAccount
$password = $yourAdminPassword
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $securePassword)  
$vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $VMName -Credential $cred
$vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $AzureImage.PublisherName -Offer $AzureImage.Offer -Skus $AzureImage.Skus -Version $AzureImage.Version
$vm = Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskVhdUri -name $osDiskName -CreateOption fromImage -Caching $osDiskCaching

$vm = Set-AzureRmVMBootDiagnostics -VM $vm -Disable

#Add two data disks
$dataDisk1VhdUri = "https://$randSAName.blob.core.windows.net/vhds/"+$VMName+"-Data1.vhd"
$dataDisk1Name = $VMName+'-data1Disk'
$vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDisk1Name -Caching None -CreateOption Empty -DiskSizeInGB 127 -VhdUri $dataDisk1VhdUri -Lun 1
$dataDisk2VhdUri = "https://$randSAName.blob.core.windows.net/vhds/"+$VMName+"-Data2.vhd"
$dataDisk2Name = $VMName+'-data2Disk'

$vm = Add-AzureRmVMDataDisk -VM $vm -Name $dataDisk2Name -Caching None -CreateOption Empty -DiskSizeInGB 512 -VhdUri $dataDisk2VhdUri -Lun 2

# Create Virtual Machine
Write-Output "Creating the VM" | timestamp
$NewVM = New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $Location -VM $vm 
Write-Output "VM creation complete" | timestamp

###create scripts container
New-AzureStorageContainer -Name $scriptsContainer -Context $storageAcct.Context -Permission Off

#download locally First and Second Boot Script and edit the Storage Account Keys and passwords
New-Item -Path c:\ -Name Temp -ItemType Directory
DownloadFilesFromRepo -Owner itsokov -Repository AzureSharePoint2016Install  -DestinationPath C:\Temp\

$script=Get-Content C:\temp\BootScripts\FirstBoot.ps1
$script -ma



#Now make a DC by running the first boot script

$ScriptBlobURL = "https://$randSAName.blob.core.windows.net/scripts/"
 
$ScriptName = "FirstBoot.ps1"
$ExtensionName = 'FirstBootScript'
$ExtensionType = 'CustomScriptExtension' 
$Publisher = 'Microsoft.Compute'  
$Version = '1.8'
$timestamp = (Get-Date).Ticks
 
$ScriptLocation = $ScriptBlobURL + $ScriptName
$ScriptExe = ".\$ScriptName"
 
$PrivateConfiguration = @{"storageAccountName" = "$$randSAName";"storageAccountKey" = "$ScriptBlobKey"} 
$PublicConfiguration = @{"fileUris" = [Object[]]"$ScriptLocation";"timestamp" = "$timestamp";"commandToExecute" = "powershell.exe -ExecutionPolicy Unrestricted -Command $ScriptExe"}
 
Write-Output "Injecting First Boot PowerShell" | timestamp
Set-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Location $Location `
 -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionType -TypeHandlerVersion $Version `
 -Settings $PublicConfiguration -ProtectedSettings $PrivateConfiguration
 
((Get-AzureRmVM -Name $VMName -ResourceGroupName $resourceGroupName -Status).Extensions | Where-Object {$_.Name -eq $ExtensionName}).Substatuses

Write-Output "Waiting 5 minutes for reboot to complete" | timestamp
Start-Sleep -Seconds 300 #Wait 5 minutes

#Have to remove the previous before creating a new one
Remove-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Name FirstBootScript -Force

#Now run the second boot script to install SQL and SharePoint
$ScriptName = "SecondBoot.ps1"
$ExtensionName = 'SecondBootScript'
$timestamp = (Get-Date).Ticks
 
$ScriptLocation = $ScriptBlobURL + $ScriptName
$ScriptExe = ".\$ScriptName"
 
$PrivateConfiguration = @{"storageAccountName" = "$$randSAName";"storageAccountKey" = "$ScriptBlobKey"} 
$PublicConfiguration = @{"fileUris" = [Object[]]"$ScriptLocation";"timestamp" = "$timestamp";"commandToExecute" = "powershell.exe -ExecutionPolicy Unrestricted -Command $ScriptExe"}
 
Write-Output "Injecting Second Boot PowerShell" | timestamp
Set-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Location $Location `
 -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionType -TypeHandlerVersion $Version `
 -Settings $PublicConfiguration -ProtectedSettings $PrivateConfiguration
 
((Get-AzureRmVM -Name $VMName -ResourceGroupName $resourceGroupName -Status).Extensions | Where-Object {$_.Name -eq $ExtensionName}).Substatuses

Remove-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Name SecondBootScript -Force

Write-Output "Installation complete" | timestamp

#endregion JohnSavill













net use $driveToMap "\\$randSAName.file.core.windows.net\$storageAccountShareName" $ScriptBlobKey[0].Value /user:$randSAName
#New-Item -Path "$driveToMap" -ItemType Directory -Name 'SharePointInstall'
(New-Object System.Net.WebClient).DownloadFile($sharepointBinaryUrl, $sharepointBinaryLocation)


### download SQL image
(New-Object System.Net.WebClient).DownloadFile($sqlBinaryUrl, $sharepointBinaryLocation)

### download GitHub Scripts and Config and create folder structure
#(New-Object System.Net.WebClient).DownloadFile($autoSPInstallerScriptsUrl, "$driveToMap\autospinstaller.zip")




### edit passwords in autospinstaller config
$xml=Get-Content "$driveToMap\SP\AutoSPInstaller\AutoSPInstallerInput.xml"
$xml=$xml -replace "QD59r3cDZk74pYdYxF87", $yourAdminPassword
Set-Content -Value $xml -Path "$driveToMap\SP\AutoSPInstaller\AutoSPInstallerInput.xml"

### extract sharepoint and SQL images

$mountIso=Mount-DiskImage -ImagePath "$driveToMap\SQLServer2016SP2-FullSlipstream-x64-ENU.iso" -PassThru
$isoDriveLetter = ($mountIso | Get-Volume).DriveLetter

Copy-Item -Container "$isoDriveLetter`:" -Destination "$driveToMap\SQLMedia" -Recurse
Dismount-DiskImage -InputObject $mountIso

#extract SharePoint iso


function DownloadFilesFromRepo {
Param(
    [string]$Owner,
    [string]$Repository,
    [string]$Path,
    [string]$DestinationPath
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $baseUri = "https://api.github.com/"
    $args = "repos/$Owner/$Repository/contents/$Path"
    $wr = Invoke-WebRequest -Uri $($baseuri+$args)
    $objects = $wr.Content | ConvertFrom-Json
    $files = $objects | where {$_.type -eq "file"} | Select -exp download_url
    $directories = $objects | where {$_.type -eq "dir"}
    
    $directories | ForEach-Object { 
        DownloadFilesFromRepo -Owner $Owner -Repository $Repository -Path $_.path -DestinationPath $($DestinationPath+$_.name)
    }

    
    if (-not (Test-Path $DestinationPath)) {
        # Destination path does not exist, let's create it
        try {
            New-Item -Path $DestinationPath -ItemType Directory -ErrorAction Stop
        } catch {
            throw "Could not create path '$DestinationPath'!"
        }
    }

    foreach ($file in $files) {
        $fileDestination = Join-Path $DestinationPath (Split-Path $file -Leaf)
        try {
            Invoke-WebRequest -Uri $file -OutFile $fileDestination -ErrorAction Stop -Verbose
            "Grabbed '$($file)' to '$fileDestination'"
        } catch {
            throw "Unable to download '$($file.path)'"
        }
    }

}
