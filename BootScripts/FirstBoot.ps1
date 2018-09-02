#region variables

$netbiosname = 'contoso'
$fqdomname = "$netbiosname.local"

#endregion

#Bring data disks online and initialize them
Get-Disk | Where-Object PartitionStyle –Eq "RAW"| Initialize-Disk -PartitionStyle GPT   
#Change CD drive letter
$drv = Get-WmiObject win32_volume -filter 'DriveLetter = "E:"'
$drv.DriveLetter = "L:"
$drv.Put() | out-null
                    
Get-Disk -Number 2 | New-Partition -UseMaximumSize -DriveLetter E | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data1" -Confirm:$False      
Get-Disk -Number 3 | New-Partition -UseMaximumSize -DriveLetter F | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data2" -Confirm:$False      

#Install AD
Import-Module "Servermanager" #For Add-WindowsFeature
Add-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

$SafePassPlain = 'Pa55word'
$SafePass = ConvertTo-SecureString -string $SafePassPlain `
    -AsPlainText -force

$NTDSPath = 'e:\ntds'
$NTDSLogPath = 'e:\ntdslogs'
$SYSVOLPath = 'e:\sysvol'
  
Install-ADDSForest -DomainName $fqdomname -DomainNetBIOSName $netbiosname `
	-SafemodeAdministratorPassword $SafePass -SkipPreChecks `
	-InstallDNS:$true -SYSVOLPath $SysvolPath -DatabasePath $NTDSPath -LogPath $NTDSLogpath `
	-Force