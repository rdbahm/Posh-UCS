<#
To enable phone state polling, these settings must be set:
apps.statePolling.responseMode = 0
apps.statePolling.username = user-selected
apps.statePolling.password = user-selected

Also for some reason, the requirement for a secure tunnel is set with a push parameter:
apps.push.secureTunnelRequired= 0
#>

<#### FUNCTION DEFINITONS ####>

<## Phone Functions ##>

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
        
        $SipAddress = $null
        Foreach($DN in $PhoneDNs)
        {
          $null = $DN -match '[^@&=+$,:;\?/]+@[^@&=+$:,;\?/]+'
          $ThisSipAddress = $Matches[0]
          $ThisSipAddress = ('sip:{0}' -f $ThisSipAddress)
          
          #If we have only one, we return it as a bare string. Otherwise, we make an ArrayList.
          if($SipAddress -eq $null)
          {
            $SipAddress = $ThisSipAddress
          }
          elseif($SipAddress.Count -gt 1)
          {
            $null = $SipAddress.Add($ThisSipAddress)
          }
          else
          {
            $NewSipAddress = New-Object System.Collections.ArrayList
            $null = $NewSipAddress.Add($ThisSipAddress)
            $null = $NewSipAddress.Add($SipAddress)
            $SipAddress = $NewSipAddress
          }
        }
        
        $SipAddress = $SipAddress | Sort-Object -Unique #Remove duplicates.
        
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

Function Get-UcsPollCall
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
        Foreach($ThisCall in $Line.CallInfo)
        {
          #Most cmdlets return "remote" and "local" party info. Poll returns "called" and "calling."
          if($ThisCall.CallType -eq "Outgoing")
          {
            $LocalPartyName = $ThisCall.CallingPartyName
            $LocalPartyNumber = $ThisCall.CallingPartyDirNum
            $RemotePartyName = $ThisCall.CalledPartyName
            $RemotePartyNumber = $ThisCall.CalledPartyDirNum
          }
          else
          {
            $LocalPartyName = $ThisCall.CalledPartyName
            $LocalPartyNumber = $ThisCall.CalledPartyDirNum
            $RemotePartyName = $ThisCall.CallingPartyName
            $RemotePartyNumber = $ThisCall.CallingPartyDirNum
          }

          #Older firmware versions (4.1.4 was tested) don't return a protocol for a call.
          $ThisCallObject = New-UcsCallObject `
            -Type $ThisCall.CallType `
            -CallHandle $ThisCall.CallReference `
            -Duration (New-TimeSpan -Seconds $ThisCall.CallDuration) `
            -Protocol $ThisCall.Protocol.ToUpper() `
            -CallState $ThisCall.CallState `
            -RemotePartyName $RemotePartyName `
            -RemotePartyNumber $RemotePartyNumber `
            -LocalPartyName $LocalPartyName `
            -LocalPartyNumber $LocalPartyNumber `
            -LineId $ThisCall.LineId `
            -Muted ([Int]$ThisCall.Muted) `
            -Ringing ([Int]$ThisCall.Ringing) `
            -UIAppearanceIndex $ThisCall.UiAppearanceIndex `
            -IPv4Address $ThisIPv4Address `
            -ExcludeNullProperties
          $null = $AllResults.Add($ThisCallObject)
        }
      }      
    }
  }
  End
  {
    Return $AllResults
  }
}