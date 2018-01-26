function global:Update-RDMS {
    <#
        .Synopsis
        Ensure all RDS deployment servers are added to the Remote Desktop Management Server (Server Manager)

        .Description
        This cmdlet queries the Connection Broker and updates Server Manager to ensure all the RDS servers are added.
        Server Manager is killed if running, updated and restarted.

        .Example
        Update-RDMS
        Updates the RDMS

        .Notes
        RCM August 2015

        .Link
        http://www.rcmtech.co.uk/
    #>
    Begin{}
    Process{
        Write-Debug "Starting Update-RDMS"

        $ConnectionBrokers = "CBR01.rcmtech.co.uk","CBR02.rcmtech.co.uk"
        $ServerManagerXML = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\ServerManager\Serverlist.xml"
        Write-Debug "Import RDS cmdlets"
        Import-Module RemoteDesktop
        Write-Debug "Find active Connection Broker"
        $ActiveManagementServer = $null
        foreach($Broker in $ConnectionBrokers){
            $ActiveManagementServer = (Get-ConnectionBrokerHighAvailability -ConnectionBroker $Broker).ActiveManagementServer
            if($ActiveManagementServer -eq $null){
                Write-Host "Unable to contact $Broker" -ForegroundColor Yellow
            } else {
                break
            }
        }
        if($ActiveManagementServer -eq $null){
            Write-Error "Unable to contact any Connection Broker"
        }else{
            if(Get-Process -Name ServerManager -ErrorAction SilentlyContinue){
                Write-Debug "Kill Server Manager"
                # Have to use tskill as stop-process gives an "Access Denied" with ServerManager
                Start-Process -FilePath "$env:systemroot\System32\tskill.exe" -ArgumentList "ServerManager"
            }
            Write-Debug "Get RD servers"
            $RDServers = Get-RDServer -ConnectionBroker $ActiveManagementServer
            Write-Debug "Get Server Manager XML"
            [XML]$SMXML = Get-Content -Path $ServerManagerXML
            foreach($RDServer in $RDServers){
                $Found = $false
                Write-Host ("Checking "+$RDServer.Server+" ") -NoNewline -ForegroundColor Gray
                foreach($Server in $SMXML.ServerList.ServerInfo){
                    if($RDServer.Server -eq $Server.name){
                        $Found = $true
                    }
                }
                if($Found -eq $true){
                    Write-Host "OK" -ForegroundColor Green
                }else{
                    Write-Host "Missing" -ForegroundColor Yellow
                    $NewServer = $SMXML.CreateElement("ServerInfo")
                    $SMXML.ServerList.AppendChild($NewServer) | Out-Null
                    $NewServer.SetAttribute("name",$RDServer.Server)
                    $NewServer.SetAttribute("status","1")
                    $NewServer.SetAttribute("lastUpdateTime",[string](Get-Date -Format s))
                    $NewServer.SetAttribute("locale","en-GB")
                }
            }
            # Remove xmlns attribute on any newly added servers, this is added automatically by PowerShell but causes Server Manager to reject the new server
            $SMXML = $SMXML.OuterXml.Replace(" xmlns=`"`"","")
            Write-Debug "Save XML file"
            $SMXML.Save($ServerManagerXML)
            Write-Debug "Start Server Manager"
            Start-Process -FilePath "$env:systemroot\System32\ServerManager.exe"
        }
    }
    End{}
}
