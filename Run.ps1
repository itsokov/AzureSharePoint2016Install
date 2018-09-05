#region variables

$resourceGroupName="SP2016Dev7"
$location="WestEurope"
$sharepointBinaryUrl='https://itsokov.blob.core.windows.net/installblob/officeserver.img'
$sqlBinaryUrl='https://itsokov.blob.core.windows.net/installblob/SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
$storageAccountShareName="assets"
$randSAName= -join ((97..122) | Get-Random -Count 9 | % {[char]$_})
$SASKU = 'Standard_LRS'
#$driveToMap='X:'
$yourAdminPassword=Read-Host -Prompt "Please enter the password you will use for all accounts"
$VirtNetName = 'VNPOC1'
$VMName = -join ((97..122) | Get-Random -Count 9 | % {[char]$_})
$VMSize ="Standard_DS3_v2"
$ServerSKU="2016-Datacenter"
$setupAccount='sp_setup'
$scriptsContainer="scripts"
$gitHubAssets='https://github.com/itsokov/AzureSharePoint2016Install/archive/master.zip'
$netbiosname='contoso'
#endregion



#Login-AzureRmAccount
#(Get-AzureRmSubscription)[1] | Select-AzureRmSubscription
(Get-AzureRmContext -ListAvailable)[0] | Select-AzureRmContext
$resourceGroup=New-AzureRmResourceGroup "$resourceGroupName" -Location $location

$storageAcct=New-AzureRmStorageAccount -Name $randSAName -ResourceGroupName $resourceGroupName -SkuName $SASKU -Location $location 
#$storageAccountShare=New-AzureStorageShare  -Name $storageAccountShareName  -Context $storageAcct.Context 
$ScriptBlobKey = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $randSAName
$ScriptBlobKey=$ScriptBlobKey[0].Value
start-sleep -Seconds 10
#net use $driveToMap "\\$randSAName.file.core.windows.net\$storageAccountShareName" $ScriptBlobKey /user:$randSAName

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

#download locally Scripts from GitHyb and edit the Storage Account Keys and passwords
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


$script=Get-Content C:\temp\BootScripts\FirstBoot.ps1
$script=$script -replace "<your admin pass>",$yourAdminPassword
$script=$script -replace "<your netbios name>",$netbiosname
Set-Content -Value $script -Path C:\temp\BootScripts\FirstBoot.ps1 -Encoding UTF8

$script=Get-Content C:\temp\BootScripts\SecondBoot.ps1
$script=$script -replace "<your admin pass>",$yourAdminPassword
#$script=$script -replace "<storage account name>",$randSAName
#$script=$script -replace "<storage account key>",$ScriptBlobKey
#$script=$script -replace "<SAShareName>",$storageAccountShareName
$script=$script -replace "<your netbios name>",$netbiosname
#$script=$script -replace "<drive to map>",$driveToMap
$script=$script -replace "<sharePoint iso source>",$sharepointBinaryUrl
$script=$script -replace "<SQL Binary URL>",$sqlBinaryUrl
$script=$script -replace "<GitHub Assets>",$gitHubAssets
$script=$script -replace "<Setup Account>",$setupAccount
Set-Content -Value $script -Path C:\temp\BootScripts\SecondBoot.ps1 -Encoding UTF8



#Upload these scripts to the blob or file share

$blobName = "FirstBoot.ps1" 
$localFile = "C:\Temp\BootScripts\$blobName" 
Set-AzureStorageBlobContent -File $localFile -Container $scriptsContainer -Blob $blobName -Context $storageAcct.Context -Force

$blobName = "SecondBoot.ps1" 
$localFile = "C:\Temp\BootScripts\$blobName" 
Set-AzureStorageBlobContent -File $localFile -Container $scriptsContainer -Blob $blobName -Context $storageAcct.Context -Force




#Now make a DC by running the first boot script

$ScriptBlobURL = "https://$randSAName.blob.core.windows.net/$scriptsContainer/"
 
$ScriptName = "FirstBoot.ps1"
$ExtensionName = 'FirstBootScript'
$ExtensionType = 'CustomScriptExtension' 
$Publisher = 'Microsoft.Compute'  
$Version = '1.9'
$timestamp = (Get-Date).Ticks
 
$ScriptLocation = $ScriptBlobURL + $ScriptName
$ScriptExe = ".\$ScriptName"
 
$PrivateConfiguration = @{"storageAccountName" = "$randSAName";"storageAccountKey" = "$ScriptBlobKey"} 
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
 
$PrivateConfiguration = @{"storageAccountName" = "$randSAName";"storageAccountKey" = "$ScriptBlobKey"} 
$PublicConfiguration = @{"fileUris" = [Object[]]"$ScriptLocation";"timestamp" = "$timestamp";"commandToExecute" = "powershell.exe -ExecutionPolicy Unrestricted -Command $ScriptExe"}
 
Write-Output "Injecting Second Boot PowerShell" | timestamp
Set-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Location $Location `
 -Name $ExtensionName -Publisher $Publisher -ExtensionType $ExtensionType -TypeHandlerVersion $Version `
 -Settings $PublicConfiguration -ProtectedSettings $PrivateConfiguration
 
((Get-AzureRmVM -Name $VMName -ResourceGroupName $resourceGroupName -Status).Extensions | Where-Object {$_.Name -eq $ExtensionName}).Substatuses

Remove-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $VMName -Name SecondBootScript -Force

Write-Output "Installation complete" | timestamp

#endregion JohnSavill



###delete share and blob container

