# Created by: drewskinator99
# skip EULA
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false -InformationAction SilentlyContinue
Write-Host "`n`n****************************************************************`n`n`tRunning vSphere Script...`n`n****************************************************************`n"
Write-Host "`n`n`n --- Connecting to local vsphere instance: --- `t`n`n"
# Get server information
$server = Read-Host "Enter the vcenter dns hostname: "
Write-Host "`n`nA window will appear to enter your credentials..." -ForegroundColor Cyan
Start-Sleep -Seconds 1
$error.Clear()
# Get credentails and connect to vsphere
$creds = Get-Credential
Write-Host "`n --- Connecting... --- `t`n" 
Connect-VIServer $server -Credential $creds -ErrorAction SilentlyContinue
if($error){
    Write-Host "`n`n`tERROR:`tIncorrect Username, password, or server name. Please check all 3 and try again.`n`n" -ForegroundColor Yellow 
    Read-Host "`tPress any key to quit "
    exit -1
}
Write-Host "`n`n`n`t --- Connection Successful! --- `t`n`n" -ForegroundColor Green
$finalchoice = "1"
while($finalchoice -ne "0"){
    # provide choices to the user
    Write-Host "`n`nWelcome to the VSphere Script.`n`n`tWhat would you like to do?`n`n`t`t1: Get List of NICS not running VMXNet`n`t`t `
                2: Get List of VM's running outdated VMTools`n`t`t 3: Get VM Encryption Info`n`t`t`n`t`t `4: Get a list of VM's that are powered on`n`t`t`n`t`t `
                5: Get BIOS information`n`t`t6: Get Admin Rights Information`n`t`t0: Quit`n`n" -ForegroundColor Cyan
    $choices = Read-Host "`n`nMake your selection: " 
    # Get VM's
    $allvms = Get-VM
    ### Choose a datacenter name
    $DatacenterName = Get-Datacenter 
    ### Get all VMs in the chosen datacenter
    $vms2 = $DatacenterName | Get-VM | Sort-Object
    $vms3 = $vms2 | Where-Object {$_.PowerState -eq "PoweredOn"} 
    $vms = $allvms | where-object {$_.Powerstate -eq "PoweredOn"} 
    switch($choices){
    "1" { # NIC Adapters
            $adapterlist =  $vms | Get-NetworkAdapter | Where-object {$_.Type -ne "Vmxnet3"} | Select Parent, Type | where-object {($_.Parent -notmatch ".*/") -and ($_.Parent -notmatch ".*_replica")} | sort Parent
            Write-Host "`n`n`n --- List of Adapters: --- `t`n`n" 
            $adapterlist | ft
            $path = Join-Path -Path $env:USERPROFILE -Childpath "Documents\nicInfo.csv" 
            Write-Host "`n`n`n --- Writing Results to $path --- `t`n`n" -ForegroundColor Cyan
            $adapterlist  | export-csv $path -NoTypeInformation
            $vmguests = $vms | Get-VMguest | select VMName, ToolsVersion | where-object {($_.VmName -notmatch ".*/") -and ($_.VmName -notmatch ".*_replica")} | where-object {$_.ToolsVersion -and $_.ToolsVersion -ne "11.3.5"} | sort VMName
        }
    "2" { # VmWare Tool Versions           
            $vmguests = $vms | Get-VMguest | select VMName, ToolsVersion | where-object {($_.VmName -notmatch ".*/") -and ($_.VmName -notmatch ".*_replica")} | where-object {$_.ToolsVersion -and $_.ToolsVersion -ne "11.3.5"} | sort VMName
            Write-Host "`n`n`n --- List of VMWareTools: --- `t`n`n" 
            $vmguests | ft
            $path = Join-Path -Path $env:USERPROFILE -Childpath "Documents\vmwwaretools.csv" 
            Write-Host "`n`n`n --- Writing Results to $path --- `t`n`n" -ForegroundColor Cyan
            $vmguests | export-csv $path -NoTypeInformation
        }
    "3" { # Encrypted VM's
            # Have to change execution policy to get this to run
            $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
            Import-Module -Name VMWare.vMEncryption
            # switch execution policy back
            Set-ExecutionPolicy -ExecutionPolicy $executionPolicy -scope CurrentUser -Force 
            Write-Host "`n`n`n --- List of Encrypted VM's: --- `t`n`n" 
            $path = Join-Path -Path $env:USERPROFILE -Childpath "Documents\EncryptedVMs.csv"
            # create new file, remove existing if applicable 
            if(test-path $path){
                Remove-Item -Path $path -Force -ErrorAction SilentlyContinue -InformationAction SilentlyContinue -WarningAction SilentlyContinue
            }
            Write-Host "`n`n`n --- Writing Results to $path --- `t`n`n" -ForegroundColor Cyan 
            # Find encrypted vm's, print to screen and output to csv
            foreach ($vm in $vms){
                $encrypted = $vm | Get-VMEncryptionInfo
                if($encrypted.profile){
                    $vm | select Name | export-csv $path -NoTypeInformation -append 
                    Write-Host $vm -ForegroundColor Cyan
                }   
            }              
        }
    "4" { # Powered On VM's
            Write-Host "`n`n`n --- List of Powered On VM's: --- `t`n`n"
            ### Check to see if the report is empty
            if (!$vms3) {
                Write-Host -ForegroundColor Red `n "No VMs found."
                continue
            }
            # Generate reports and print results to screen
            Write-Host $vms3 -ForegroundColor Cyan
            Write-Host `n "Generating CSV > C:\Path\$DatacenterName-PoweredOnVMs-$date.csv"
            $vms3 | Export-CSV -path ".\$DatacenterName-PoweredOnVMs-$date.csv" -NoTypeInformation
        }
    "5" { # BIOS Enabled VM's
            Write-Host "`n`n`n --- List of BIOS Enabled VM's: --- `t`n`n"
            $report = foreach ($vm in $vms3) {
                ### Display a progress bar during VM checks
                Write-Progress -Activity "Scanning for BIOS-enabled VMs..." -Status "Checking $vm" -PercentComplete ($loop/$vms.count * 100)
                ### If the VM boot firmware is set to BIOS, add it to the report
                $vm | Select-Object Name,@{N='Firmware';E={$_.ExtensionData.Config.Firmware}}
            }       
            ### Check to see if the report is empty
            if (!$report) {
                Write-Host -ForegroundColor Red `n "No BIOS-enabled VMs found."
                continue
            }
            # Generate reports
            Write-Host $report -ForegroundColor Cyan       
            Write-Host `n "Generating CSV > C:\Path\$DatacenterName-New-BIOS-VM-Report-$date.csv"
            $report | Export-CSV -path ".\$DatacenterName-BIOS-VM-Report-$date.csv" -NoTypeInformation       
        }
    "6" {   # Admin rights on VM's
            Write-Host "`n`n`n --- Printing List of VM Admins to Files --- `t`n`n"        
            foreach ($vm in $vms3) {
                $report += Get-VIPermission -Entity $vm | select Principal | where-object {$_.Principal -eq "VsphereName.local\Administrators"}
                $Admins += Get-VIPermission $vm | select Principal, Role | Where-Object{$_.Role -eq "Admin"}    
            }
            ### Check to see if the report is empty
            if (!$report -or !$Admins) {
                Write-Host -ForegroundColor Red `n "No Admins found."
                continue
            }    
            # Generate reports   
            Write-Host `n "Generating CSV > C:\Path\$DatacenterName-VsphereAdmins-$date.csv"
            $report | Export-CSV -path ".\$DatacenterName-VsphereAdmins-$date.csv" -NoTypeInformation
            Write-Host `n "Generating CSV > C:\Path\$DatacenterName-Admins-$date.csv"
            $Admins | Export-CSV -path ".\$DatacenterName-Admins-$date.csv" -NoTypeInformation 
        }    
    "0" { # Exit
            Write-Host "Thank you! Program exiting." -ForegroundColor Green
            Start-Sleep -Seconds 3
            $finalchoice = $choices
            break
        }
    default { # Try again
            Write-Host "`n`n`tWrong Choice! Try Again." -ForegroundColor Red
            continue
        }     
    }
    $finalchoice = $choices
}
if($error){
	Write-Host "`n`n`n`t --- Errors were found in the script. Please check filepaths.  --- `t`n`n" -ForegroundColor Red
}
else{
    Write-Host "`n`n`n`t --- Script Executed Successfully!  --- `t`n`n" -ForegroundColor Green
}
Read-Host "Press any key to quit "
Exit 0