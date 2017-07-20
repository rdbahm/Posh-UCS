<#
To enable phone state polling, these settings must be set:
apps.statePolling.responseMode = 0
apps.statePolling.username = user-selected
apps.statePolling.password = user-selected

Also for some reason, the requirement for a secure tunnel is set with a push parameter:
apps.push.secureTunnelRequired= 0
#>
Function Get-UcsPollDeviceInfo
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )

  Begin
  {
    $AllResults = New-Object Collections.ArrayList
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisResult = Invoke-UcsPollRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'polling/deviceHandler' -ErrorAction Stop
      }
      Catch
      {
        Write-Error "Couldn't get device information from $ThisIPv4Address."
        Continue
      }
      
      Try
      {
        $Matches = $null
        $null = $ThisResult.AppLoadID -match '^\d+\.\d+\.\d+\.\d+(?=\s)'
        $FirmwareRelease = $Matches[0]
      }
      Catch
      {
        Write-Debug "Couldn't get a firmware version."
      }

      Try
      {
        $Matches = $null
        $PhoneDNs = $ThisResult.PhoneDN.Split(',')
        $PhoneDN = $PhoneDNs[0] #We're dropping all results but the first one because I'm in a Skype for Business environment and can't be bothered.
        $null = $ThisResult.PhoneDN -match '(?<=:).+@.+$'
        $SipAddress = $Matches[0]
      }
      Catch
      {
        Write-Debug "Couldn't get a SIP address."
      }

      $FinalResult = $ThisResult | Select-Object @{Name='MacAddress';Expression={$_.MACAddress}},@{Name='Model';Expression={$_.ModelNumber}},@{Name='FirmwareRelease';Expression={$FirmwareRelease}},@{Name='SipAddress';Expression={$SipAddress}},@{Name='IPv4Address';Expression={$ThisIPv4Address}}
      
      $null = $AllResults.Add($FinalResult)
    }
  }
  End
  {
    Return $AllResults
  }
}

Function Get-UcsPollNetworkInfo
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )

  Begin
  {
    $AllResults = New-Object Collections.ArrayList
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisResult = Invoke-UcsPollRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'polling/networkHandler' -ErrorAction Stop
      }
      Catch
      {
        Write-Error "Couldn't get device information from $ThisIPv4Address."
        Continue
      }
      
      if($ThisResult.DHCPEnabled -eq 'yes')
      {
        $DHCPEnabled = $true
      }
      elseif($ThisResult.DHCPEnabled -eq 'no')
      {
        $DHCPEnabled = $false
      }
      else
      {
        $DHCPEnabled = $null
      }
      
      $FinalResult = $ThisResult | Select-Object SubnetMask,VLANID,DHCPServer,@{Name='DNSDomain';Expression={$_.DNSSuffix}},@{Name='ProvServerAddress';Expression={$_.ProvServer}},@{Name='DefaultGateway';Expression={$_.DefaultRouter}},@{Name='DNSServer';Expression={$_.DNSServer1}},@{Name='AlternateDNSServer';Expression={$_.DNSServer2}},@{Name='DHCPEnabled';Expression={$DHCPEnabled}},@{Name='MacAddress';Expression={$_.MACAddress}},@{Name='IPv4Address';Expression={$ThisIPv4Address}}
      
      $null = $AllResults.Add($FinalResult)
    }
  }
  End
  {
    Return $AllResults
  }
}

Function Get-UcsPollCallStatus
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )

  Begin
  {
    $AllResults = New-Object Collections.ArrayList
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisResult = Invoke-UcsPollRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'polling/callstateHandler' -ErrorAction Stop
      }
      Catch
      {
        Write-Error "Couldn't get call information from $ThisIPv4Address."
        Continue
      }
      
      #There can be multiple lines, and each call can have multiple lines. We're going to create a call object for each.
      
      Foreach($Line in $ThisResult)
      {
        Foreach($Call in $Line.CallInfo)
        {
          $Ringing = [Bool]$Line.Ringing
          $Muted = [Bool]$Line.Muted
          if($Call.UIAppearanceIndex -match '^\d+\*$')
          {
            $ActiveCall = $true
          }
          elseif ($Call.UIAppearanceIndex -match '^\d+$')
          {
            $ActiveCall = $false
          }
          else
          {
            $ActiveCall = $null
          }
          $UIAppearanceIndex = $Call.UiAppearanceIndex.Trim(' *')
          $ThisOutput = $Call | Select-Object Protocol,CallState,@{Name='Type';Expression={$_.CallType}},@{Name='CallHandle';Expression={('0x{0}' -f $_.CallReference)}},@{Name='RemotePartyName';Expression={$_.CalledPartyName}},@{Name='RemotePartyNumber';Expression={$_.CalledPartyDirNum}},@{Name='RemoteMuted';Expression={$Muted}},@{Name='Ringing';Expression={$Ringing}},@{Name='Duration';Expression={New-Timespan -Seconds $_.CallDuration}},@{Name='LineId';Expression={$Line.LineKeyNum}},@{Name='SipAddress';Expression={$Line.LineDirNum}},@{Name='ActiveCall';Expression={$ActiveCall}},@{Name='UIAppearanceIndex';Expression={$UIAppearanceIndex}},@{Name='IPv4Address';Expression={$ThisIPv4Address}}
          $null = $AllResults.Add($ThisOutput)
        }
      }
      
      
    }
  }
  End
  {
    Return $AllResults
  }
}