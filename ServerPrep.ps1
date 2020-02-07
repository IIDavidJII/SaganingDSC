Configuration ATIServerPrep 
{
  Param
    ( [String]
      $TimeZone = 'Eastern Standard Time',

      [String]
      $OasisUser = 'sagchip\OasisService',

      [String]
      $LoyaltyUser = 'comanche\svcLoyalty',
      
      [String]
      $timeStamp = (Get-Date).tostring()
    )

Import-DscResource -ModuleName 'PSDesiredStateConfiguration','NetworkingDSC' , 'xSystemSecurity', 'cDTC', 'ComputerManagementDsc'

Node $AllNodes.NodeName {

#remote Desktop
 WindowsFeature RemoteAccess {
   Ensure = "Present"
   Name = "RemoteAccess"
 }

 WindowsFeature RemoteAccessDesktop {
   Ensure = "Present"
   Name = "Remote-Desktop-Services"
 }

#Disable Firewall
  Service MpsSvc
  {
    Name = "MpsSvc"
    StartupType = "Automatic"
    State = "Running"
  }

  Script DisableFirewalls
     {
       GetScript = {(Get-NetFirewallProfile -All -ErrorAction SilentlyContinue).Enabled}

       TestScript = {
                       IF((Get-NetFirewallProfile -all -ErrorAction SilentlyContinue).Enabled) 
                            {return $true} 
                       ELSE {return $false} 
                    }
       SetScript = {Set-NetFIrewallProfile -all -Enabled False}
     }
#allow DTC through firewall

  Script AllowDTCappfirewall
    {
       GetScript = {Get-NetFirewallRule -DisplayGroup "Distributed Transaction Coordinator" }

       Testscript = {
                      IF ((Get-NetFirewallRule -DisplayGroup "Distributed Transaction Coordinator").Enabled -eq $true)
                           {Return $true}
                      Else {Return $false}
                    }

       SetScript =  {
                      Set-NetFirewallRule -DisplayGroup "Distributed Transaction Coordinator" -Enabled True 
                    }
    }
    
#TimeZone
    TimeZone SetTimeZone
     {
       IsSingleInstance = 'Yes'
       TimeZone = $TimeZone
     }


#install required windows features

    WindowsFeature MessageQueuing 
     {
      Name = "MSMQ"
      Ensure = "Present"
     }
    WindowsFeature MessageQueuingService 
     {
      Name = "MSMQ-Services"
      Ensure = "Present"
     }

    WindowsFeature MessageQueingServer
     {
      Name = "MSMQ-Server"
      Ensure = "Present"
     }

    WindowsFeature net35Framework
     {
      Name = "NET-Framework-Core"
      Ensure = "Present"
      Source = "\\VOASIS2016DB\DSC_Configuration"
     }

#User Account Control    
    Script DisableUAC 
     {
       TestScript = {IF((Get-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA).EnableLUA = '0') {return $True}Else {$False}}
       SetScript = {Set-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA -Value 0 -PassThru}
       GetScript = {(Get-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA).EnableLUA}
     }

#Distributed Transactions     
     cDTCNetworkSetting DistributedTrans 
     {
       DtcName = "Local"
       RemoteClientAccessEnabled = $true
       RemoteAdministrationAccessEnabled = $true
       InboundTransactionsEnabled = $true
       OutboundTransactionsEnabled = $true
       XATransactionsEnabled = $true
       LUTransactionsEnabled = $true
       AuthenticationLevel = "NoAuth"
     }

#Power Plan
     PowerPlan SetPlanHighPerformance
        {
          IsSingleInstance = 'Yes'
          Name             = 'High performance'
        }


#IPV4 disable nic Power Management
     Script DisablePowerManagement1
       {
         TestScript = {
                        $adapterPower = Get-NetAdapterPowerManagement                     
                        IF($adapterPower.ArpOffload -ne "Enabled" -and $adapterPower.NSOffload -ne "Enabled" -and $adapterPower.RsnRekeyOffload -ne "Enabled" -and $adapterPower.D0PacketCoalescing -ne "Enabled" -and $adapterPower.DeviceSleepOnDisconnect -ne "Enabled" -and $adapterPower.WakeOnMagicPacket -ne "Enabled" -and $adapterPower.WakeOnPattern -ne "Enabled" )
                        {return $true} 
                        ELSE {return $false}
                      }

         SetScript = { $AdapterPower1 = Get-NetAdapterPowerManagement
                       FOREACH($adapter1 in $AdapterPower1)
                         {Disable-NetAdapterPowerManagement -Name $adapter1.name}
                     }

         GetScript = {Get-NetAdapterPowerManagement}
       }

    Script DisablePowerManagement2
      {
       TestScript = {
                         foreach ($NIC in (Get-NetAdapter -Physical))
                          {
                            $PowerSaving = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi | ? {$_.InstanceName -match [Regex]::Escape($NIC.PnPDeviceID)}
                              if ($PowerSaving.Enable -eq $false){Return $true} ELSE {Return $false}
                          }
                    }

       SetScript = {    foreach ($NIC in (Get-NetAdapter -Physical))
                          {
                            $PowerSaving = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi | ? {$_.InstanceName -match [Regex]::Escape($NIC.PnPDeviceID)}
                              if ($PowerSaving.Enable){
                                                       $PowerSaving.Enable = $false
                                                       $PowerSaving | Set-CimInstance
                                                      }
                          }
                  }
       
       GetScript = {
                          foreach ($NIC in (Get-NetAdapter -Physical))
                          {
                            $PowerSaving = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root\wmi | ? {$_.InstanceName -match [Regex]::Escape($NIC.PnPDeviceID)}
                            $PowerSaving.Enable 
                          }

                   }
      }

#Registry edit for HTTP2
   Registry HTTP2Disable1  {
     Ensure = "Present"
     Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\HTTP\Parameters"
     ValueName = "EnableHttp2Tls"
     ValueData = "0"
     ValueType = "Dword"
   }

   Registry HTTP2Disable2 {
     Ensure = "Present"
     Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\HTTP\Parameters"
     ValueName = "EnableHttp2Cleartext"
     ValueData = "0"
     ValueType = "Dword"
   }
   
   #Disable IPv6
   Script IPV6Disable {
   TestScript = {$AdapterIVP6 = Get-NetAdapterBinding -name * -ComponentID 'MS_TCPIP6'
                 IF((Get-NetAdapterBinding  -Name * -ComponentID ms_tcpip6).Enabled-eq $false) {return $true} Else {return $false}
                 }
   SetScript = {$AdapterIVP6_1 = Get-NetAdapterBinding -name * -ComponentID 'MS_TCPIP6'
                FOREACH ($Adapter_1 in $AdapterIVP6_1)
                {Disable-NetAdapterBinding -Name $Adapter_1.Name -ComponentID 'MS_TCPIP6'}
               }
   GetScript ={Get-NetAdapterBinding -ComponentID 'MS_TCPIP6'} 
   }
 
 #add Oasis EXISTING account to local admin   
    Group Administrators 
     {
       GroupName="Administrators"
       MembersToInclude=$OasisUser
     }     
  }

#  Node $AllNodes.Where{$_.Role -eq "Oasis"}.NodeName
#  {
#    #add Oasis EXISTING account to local admin   
#    Group Administrators 
#     {
#       GroupName="Administrators"
#       MembersToInclude=$OasisUser
#     }
#  }

  


  Node $AllNodes.Where{$_.Role -eq "nconnect"}.NodeName
  {
    WindowsFeature NetworkLoadBalancer {
      Name = "NLB"
      Ensure = "Present"
    }

    File TempFolder {
         Ensure = "Present"
         Type = "Directory"
         DestinationPath = "c:\Temp"
      }

  }

#  Node $AllNodes.Where{$_.Role -eq "SQLServer"}.NodeName
#  {
#    File CopySQLConfigScript {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "t:\Temp"
#      }
#
#    File SQLConfigScript1 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\DBE_Scripts"
#      }
#
#
#
#    File SQLConfigScript2 {
#         Ensure = "Present"
#         Type = "File"
#         SourcePath = 'C:\DSC_Configuration\0.SQL Server Configuration.SQL'
#         DestinationPath = "s:\DBE_Scripts\0.SQL Server Configuration.SQL"
#         DependsOn = "[File]SQLConfigScript1"
#      }
#
#    
#    File SQLConfigScript3 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Install"
#      }
#
#    SmbShare InstallShare {
#        Name = "Install$"
#        Path = "S:\Install"
#        FullAccess = @('Everyone')
#      }
#
#   File ATSFolder {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Install\_ATS"
#      }
#
#    File SQLConfigScript4 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Reports"
#      }
#
#    SmbShare ReportsShare {
#         Name = "Reports$"
#         Path = "S:\Reports"
#         FullAccess = @("Everyone")
#      }
# 
#    File SQLConfigScript5 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Omniview"
#      }
    
#    SmbShare OmniviewShare {
#         Name = "Omniview$"
#         Path = "S:\Omniview"
#         FullAccess = @("Everyone")
#      }

#    File SQLConfigScript6 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Bills"
#      }

#    SmbShare BillsShare {
#         Name = "Bills$"
#         Path = "S:\Bills"
#         FullAccess = @("Everyone")
#      }
      
#    File SQLConfigScript7 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "S:\Tickets"
#      }

#    SmbShare TicketsShare {
#         Name = "Tickets$"
#         Path = "S:\Tickets"
#         FullAccess = @("Everyone")
#      }
#
#    File SQLConfigScript8 {
#         Ensure = "Present"
#         Type = "Directory"
#         DestinationPath = "L:\Logs"
#      }
#
#
#  }
}


#Only allowed one node name change as needed

$cd = @{
    AllNodes = @(

        @{
            NodeName = "vOasis2016DB"
            Role = "SQLServer"
            Casino = "Soaring_Eagle"
         }
        
        @{
            NodeName = "vNconn01"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }

        @{
            NodeName = "vNconn02"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }

        @{
            NodeName = "vNconn03"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }

        @{
            NodeName = "vNconn04"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }

        @{
            NodeName = "vNconn05"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }
        @{
            NodeName = "vNconn06"
            Role = "nconnect"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vMMQF2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll01"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll02"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll03"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll04"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll05"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll06"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }
       
       @{
            NodeName = "vOaPoll07"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }
 
       @{
            NodeName = "vOaPoll08"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOaPoll09"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vPMT2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vMMT2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vNCGW2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vCashGW2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }


       @{
            NodeName = "vSMT2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vSMCache01"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }


       @{
            NodeName = "vSMCache02"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vSMCache03"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vSMCache04"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime01"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime02"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime03"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime04"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime05"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vOasisPrime06"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vDiagMon2016"
            Role = "Oasis"
            Casino = "Soaring_Eagle"
         }

       @{
            NodeName = "vSagOA2016DB"
            Role = "Oasis"
            Casino = "Saganing"
         }

       @{
            NodeName = "vSagMMT2016"
            Role = "Oasis"
            Casino = "Saganing"
         }

       @{
            NodeName = "vSagPMT2016"
            Role = "Oasis"
            Casino = "Saganing"
         }

       @{
            NodeName = "vSagPoll01"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagPoll02"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagPoll03"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagPoll04"
            Role = "Oasis"
            Casino = "Saganing"
         }

       @{
            NodeName = "vSagSMMT2016"
            Role = "Oasis"
            Casino = "Saganing"
         }         
       @{
            NodeName = "vSagSMCache01"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagSMCache02"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagSMCache03"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime01"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime02"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime03"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime04"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime05"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime06"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagOAPrime07"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagNConn01"
            Role = "nconnect"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagNConn02"
            Role = "nconnect"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagNCGW2016"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagCashGW2016"
            Role = "Oasis"
            Casino = "Saganing"
         }
         
       @{
            NodeName = "vSagX2S2016"
            Role = "Oasis"
            Casino = "Saganing"
         }
                        )
}
ATIServerPrep -ConfigurationData $cd -OutputPath 'C:\DSC_Configuration'
