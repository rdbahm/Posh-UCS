Function Set-UcsRestParameter 
{
  <#
      .SYNOPSIS
      Set a parameter for this specific phone.

      .DESCRIPTION
      Uses the "Set" API endpoint to set the value of a parameter.

      .PARAMETER IPv4Address
      The IP address of the target phone, in the format 192.168.1.234.

      .PARAMETER Parameter
      The name of the parameter to set.

      .PARAMETER Value
      The value to set. $True is converted to 1 and $False is converted to 0.

      .PARAMETER Quiet
      Suppresses warnings and some errors, and inhibits result output.

      .EXAMPLE
      Set-Parameter -IPv4Address Value -Parameter Value -Value Value -Quiet
      Describe what this call does

      .NOTES
      Phone may reboot after setting a parameter, especially in the case of an invalid assignment.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A valid UCS parameter, such as Up.Timeout',ValueFromPipelineByPropertyName)][String]$Parameter,
    [Parameter(Mandatory,HelpMessage = 'A valid value for the specified parameter.')][String]$Value,
  [Switch]$PassThru)

  BEGIN {
    if($Value -eq $true) 
    {
      $Value = '1'
    }
    elseif($Value -eq $false) 
    {
      $Value = '0'
    }

    $ThisParameter = Get-UcsCleanJSON -String $Parameter
    $ThisValue = Get-UcsCleanJSON -String $Value

    $ParameterSet = ("{{`"data`":{{`"{0}`": `"{1}`"}}}}" -f $ThisParameter, $ThisValue)
  } PROCESS {
    FOREACH($ThisIPv4Address in $IPv4Address) 
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        Try
        {
          $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/config/set' -Method 'Post' -Body $ParameterSet -ErrorAction Stop
        }
        Catch
        {
          Write-Error "Couldn't set parameter $Parameter with value $Value on $ThisIPv4Address. Could not connect."
        }
        
        if($ThisOutput.Status.IsSuccess -eq $false) {
          Write-Error "Couldn't set parameter $Parameter with value $Value on $ThisIPv4Address. Phone returned an error."
          Continue
        }
      }
    }

  } END {
  }
}

Function Get-UcsRestParameter 
{
  <#
      .SYNOPSIS
      Retrieve configuration parameter

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Parameter
      One or more parameter names.

      .PARAMETER Quiet
      Describe parameter -Quiet.

      .EXAMPLE
      Get-Parameter -IPv4Address Value -Parameter Value -Quiet
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-Parameter

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A UCS parameter, such as "Up.Timeout."',ValueFromPipelineByPropertyName)][String[]]$Parameter,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)
    
  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
    $MaxParameters = 20

    #TODO: The REST API only lets us request 20 parameters at a time, but we could invisibly batch them for the user. 
    if($Parameter.count -gt $MaxParameters) 
    {
      Write-Error ('{0} parameters were provided, maximum is {1}.' -f $Parameter.count, $MaxParameters) -ErrorAction Stop -RecommendedAction 'Reduce the number of parameters and try again.'
    }
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address) 
    {
      $ParameterString = ''
      Foreach($ThisParameter in $Parameter) 
      {
        $ThisParameter = Get-UcsCleanJSON -String $ThisParameter
        $ParameterString += ('"{0}",' -f $ThisParameter)
      }
      $ParameterString = $ParameterString.Substring(0,($ParameterString.Length - 1))
      
      $ParameterName = ("{{`"data`":[{0}]}}" -f $ParameterString)

      Try 
      {
        $Output = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/config/get' -Body $ParameterName -Method Post -Retries $Retries
            
        $Output = $Output.Data
      }
      Catch 
      {
        Write-Error -Message "Could not get parameter $Parameter for $ThisIPv4Address."
        Continue #No need to process more.
      }

      Try
      {
        $ParameterNames = $Output |
        Get-Member -ErrorAction Stop |
        Where-Object -Property MemberType -EQ -Value 'NoteProperty' |
        Select-Object -ExpandProperty Name
      }
      Catch 
      {
        Write-Error -Message "Could not parse parameter information for $ThisIPv4Address."
      }

      Foreach($ParameterName in $ParameterNames) 
      {
        Try 
        {
          $ThisParameterResult = $Output | Select-Object -ExpandProperty $ParameterName
          $ThisResult = $ThisParameterResult | Select-Object -Property @{
            Name       = 'IPv4Address'
            Expression = {
              $IPv4Address
            }
          }, @{
            Name       = 'Parameter'
            Expression = {
              $ParameterName
            }
          }, @{
            Name       = 'Value'
            Expression = {
              $ThisParameterResult.Value
            }
          }, @{
            Name       = 'Source'
            Expression = {
              $ThisParameterResult.Source
            }
          }
        }
        Catch 
        {
          Write-Error -Message "Couldn't create a parameter output object for $ThisIPv4Address"
          $ThisResult = $Output | Select-Object -Property @{
            Name       = 'IPv4Address'
            Expression = {
              $IPv4Address
            }
          }, @{
            Name       = 'Parameter'
            Expression = {
              $ParameterName
            }
          }, @{
            Name       = 'Value'
            Expression = {
              $null
            }
          }, @{
            Name       = 'Source'
            Expression = {
              'Error'
            }
          }
        }
      
        $null = $OutputArray.Add($ThisResult)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestNetworkInfo 
{
  <#
      .SYNOPSIS
      Returns basic networking information.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Describe parameter -Quiet.

      .EXAMPLE
      Get-NetworkInfo -IPv4Address Value -Quiet
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-NetworkInfo

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address) 
    {
      $Output = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/info' -Retries $Retries
      $Modified = $Output.data
      
      #Process the provisioning server for consistency with other cmdlets.
      $ProvisioningServer = $Modified.ProvServerAddress.Trim()
      $ProvisioningServer = $ProvisioningServer.Replace('/','\') #Make all slashes the same.
      $ProvisioningServerIndex = $ProvisioningServer.LastIndexOf('\') + 1
      if($ProvisioningServerIndex -gt 0)
      {
        $ProvisioningServer = $ProvisioningServer.Substring($ProvisioningServerIndex)
      }
      $Modified.ProvServerAddress = $ProvisioningServer
      
      
      if($Modified.DHCP -eq "enabled")
      {
        $DHCPEnabled = $true  
      } elseif($Modified.DHCP -eq "disabled")
      {
        $DHCPEnabled = $false
      } else
      {
        $DHCPEnabled = $null
      }
      $Modified = $Modified | Select-Object -ExcludeProperty DHCP -Property *,@{Name="DHCPEnabled";Expression={$DHCPEnabled}}
      $null = $OutputArray.Add($Modified)
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestDeviceInfo 
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .DESCRIPTION
      Returns model information, firmware version information, uptime, MAC address, and information on attached devices.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API call from returning warnings when problems occur.

      .EXAMPLE
      Get-DeviceInfo -IPv4Address 192.168.1.20 -Quiet
      Returns device info without returning any warnings in case of a problem.

      .NOTES
      AttachedHardware is a hashtable with multiple objects inside it representing the attached devices.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        Write-Debug -Message "Connecting to $ThisIPv4Address"
        $Output = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/device/info' -Method Get -Retries $Retries -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message "Couldn't connect to $ThisIPv4Address"
      }
                
      if($Output -ne $null) 
      {
        $Modified = $Output.data
    
        Write-Debug -Message "Connecting to $ThisIPv4Address"
        $Modified.UpTimeSinceLastReboot = Convert-UcsUptimeString -Uptime ($Modified.UpTimeSinceLastReboot)
        $LastReboot = (Get-Date) - ($Modified.UpTimeSinceLastReboot)

        $Modified = $Modified | Select-Object -ExcludeProperty ModelNumber -Property *, @{
          Name       = 'Model'
          Expression = {
            $_.ModelNumber
          }
        }, @{
          Name       = 'LastReboot'
          Expression = {
            $LastReboot
          }
        }
        #$Modified.AttachedHardware = $Modified.AttachedHardware.EM

        $null = $OutputArray.Add($Modified)
      }
    }

  } END {
    Return $OutputArray
  }
}

Function Restart-UcsRestPhone 
{
  <#
      .SYNOPSIS
      Restarts a phone.

      .DESCRIPTION
      Invokes the safeRestart API endpoint to restart the phone. The phone will not restart in the middle of a call, but will restart as soon as possible thereafter.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Describe parameter -Quiet.

      .EXAMPLE
      Restart-Phone -IPv4Address Value -Quiet
      Describe what this call does

      .NOTES
      Will generate warnings for each phone which does not successfully restart, and status objects for each phone successfully restarted. If -Quiet is specified, no output will be returned.
  #>
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$PassThru,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    #$Output = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address) 
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        Write-Verbose -Message ('Restarting {0}.' -f $ThisIPv4Address)
        Try 
        {
          $ThisResult = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/safeRestart' -Method Post -Retries $Retries -ErrorAction Stop
        }
        Catch 
        {
          Write-Debug -Message $_
          Write-Error -Message "Could not restart phone $ThisIPv4Address. Could not connect to phone."
        }

        if($ThisResult.Status.IsSuccess -ne $true) 
        {
          Write-Error -Message "Failed to restart phone $ThisIPv4Address. Phone rejected the reboot request."
          Continue
        }
      }
    }
  } END {

  }
}

Function Reset-UcsRestConfiguration
{
  <#
      .SYNOPSIS
      Restores a phone's configuration to defaults.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER ToFactoryDefaults
      Specify that the phone should be returned to factory defaults. Note: The available information does not specify the difference between the normal behavior and "ToFactoryDefaults."

      .PARAMETER ReturnResult
      Describe parameter -ReturnResult.

      .PARAMETER Quiet
      Describe parameter -Quiet.

      .EXAMPLE
      Reset-PhoneConfig -IPv4Address Value -ToFactoryDefaults -ReturnResult -Quiet
      Describe what this call does

      .NOTES
      Documentation was unavailable to determine the difference between "configReset" and "factoryReset."
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$ToFactoryDefaults,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    #$OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        Try 
        {
          if($ToFactoryDefaults) 
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/factoryReset' -Method Post -Retries $Retries -ErrorAction Stop
          }
          else 
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/configReset' -Method Post -Retries $Retries -ErrorAction Stop
          }
        }
        Catch
        {
          Write-Debug -Message $_
          Write-Error -Message "Couldn't reset $ThisIPv4Address to defaults. Could not connect to phone."
        }
        
        if($ThisOutput.Status.IsSuccess -ne $true) 
        {
          Write-Debug -Message $ThisOutput.Status
          Write-Error -Message "Couldn't reset $ThisIPv4Address to defaults. An error occurred."
          Continue
        }
      }
    }
  } END {
  }
}

Function Get-UcsRestCall 
{
  <#
      .SYNOPSIS
      Returns call status.

      .DESCRIPTION
      Returns the current status of a call, including detailed information such as the directionality of the call, the call's handle, which can be used to take certain actions on the call, and other call-related details. If no calls is currently in progress, the cmdlet returns a warning and no output. Returns only one call regardless of the number of ongoing calls.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API request from writing to the console.

      .EXAMPLE
      Get-CallStatus -IPv4Address 192.168.1.20 -Quiet
      Returns the call status of 192.168.1.20 but does not return warnings to the console in case of errors during API calls.

      .NOTES
      Tested only in Skype for Business environment.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/webCallControl/callStatus' -Retries $Retries -ErrorAction Stop
      }
      Catch 
      {
        Write-Debug -Message "Error caught: $_."
        Write-Error -Message "Couldn't get call data from $ThisIPv4Address"
        Continue
      }
      
      if($ThisOutput.data.DurationInSeconds -ne $null) 
      {
        $Modified = $ThisOutput.data
        $Duration = New-TimeSpan -Seconds ($Modified.DurationInSeconds)
        $Modified = $Modified | Select-Object -ExcludeProperty DurationInSeconds -Property *, 
              
        @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }, 
              
        @{
          Name       = 'Duration'
          Expression = {
            $Duration
          }
        }
              
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestPresence 
{
  <#
      .SYNOPSIS
      Returns presence information from the phone, if supported by the call server.

      .DESCRIPTION
      Returns the user's current presence as shown by the phone. Phone output has been modified to simplify parsing of status.

      .PARAMETER IPv4Address
      The phone's IP address in standard format: 192.168.1.20

      .EXAMPLE
      Get-Presence -IPv4Address 192.168.1.20
      Returns the presence of the phone at the specified IP address.

      .NOTES
      Tested only in Skype for Business environment.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/getPresence' -Retries $Retries -ErrorAction Stop
      }
      Catch 
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't get presence data from $ThisIPv4Address."
        Continue
      }
      
      if($ThisOutput -ne $null) 
      {
        $Modified = $ThisOutput
        $Modified = $Modified | Select-Object -Property Presence, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestLineInfo 
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .DESCRIPTION
      The LineInfo object includes information on the currently signed in user.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API request from writing to the console.

      .EXAMPLE
      Get-LineInfo -IPv4Address 192.168.1.20 -Quiet
      LineNumber         : 1
      ProxyAddress       : fakecompany.org
      Registered         : True
      Label              : John Smith
      LineType           : private
      SIPAddress         : jsmith@fakecompany.org
      Protocol           : SIP
      UserID             : John Sminth
      Port               : 0
      IPv4Address        : 192.168.1.20

      .NOTES
      Behavior has not been tested in open SIP mode.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/lineInfo' -Retries $Retries -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message "Couldn't get line info from $ThisIPv4Address."
        Continue
      }
      if($ThisOutput -ne $null) 
      {
        $Modified = $ThisOutput.data
        
        if($Modified.RegistrationStatus -eq 'registered')
        {
          $Registered = $true
        }
        elseif($Modified.RegistrationStatus -eq 'unregistered') 
        {
          $Registered = $false
        }
        else 
        {
          $Registered = $null
        }
        
        if($Modified.SIPAddress -notmatch '^.+@.+\..+$')
        {
          #For consistency of output, we don't want this to give us a fake SIP address if the phone is unregistered.
          $SIPAddress = $null
        }
        else
        {
          $SIPAddress = $Modified.SIPAddress
        }
        
        $Modified = $Modified | Select-Object -ExcludeProperty SipAddress,RegistrationStatus -Property *, @{
          Name       = 'Registered'
          Expression = {
            $Registered
          }
        }, @{
          Name       = 'SIPAddress'
          Expression = {
            $SIPAddress
          }
        }, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestSipStatus 
{
  <#
      .SYNOPSIS
      Returns advanced SIP information.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67

      .EXAMPLE
      Get-SipStatus -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-SipStatus

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/webCallControl/sipStatus' -Retries $Retries
      if($ThisOutput -ne $null) 
      {
        $Modified = $ThisOutput.data
        $Modified = $Modified | Select-Object -Property *, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestNetworkStats 
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .EXAMPLE
      Get-NetworkStats -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-NetworkStats

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/stats' -Retries $Retries
      if($ThisOutput -ne $null) 
      {
        $Modified = $ThisOutput.data
        $Modified = $Modified | Select-Object -Property *, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $Modified.UpTime = Convert-UcsUptimeString -Uptime $Modified.Uptime
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Start-UcsRestCall 
{
  <#
      .SYNOPSIS
      Dial a phone

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Destination
      Call destination. SIP addresses work (no SIP prefix needed) or you could enter something like +15555551234@example.com.

      .PARAMETER LineId
      Which line number this call should be sent on.

      .PARAMETER CallType
      Which type of call this should be. Currently, only SIP is known as a valid option.

      .PARAMETER PassThru
      Return call status information.

      .EXAMPLE
      Start-PhoneCall -IPv4Address 192.168.1.2 -Destination "+15555551234@example.com"
      Initiates a call with the PSTN number 1-555-555-1234.

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Start-PhoneCall

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>
  Param([Parameter(Position = 1,Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Position = 2,Mandatory,HelpMessage = 'The call''s destination, such as +15555555555@example.com or example@example.com')][ValidatePattern('.+@.+\..+')][String]$Destination,
    [Parameter(Position = 3)][Int][ValidateRange(1,24)]$LineId = 1,
    [Parameter(Position = 4)][String][ValidateSet('SIP')]$CallType = 'SIP',
    [Parameter(Position = 5)][Switch]$PassThru,
    [Parameter(Position = 6)][Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)
    
  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      $ThisDestination = $Destination
      $ThisDestination = Get-UcsCleanJSON -String $ThisDestination

      $DialString = ("{{`"data`":{{`"Dest`": `"{0}`",`"Line`": `"{1}`",`"Type`": `"{2}`"}}}}" -f $ThisDestination, $LineId, $CallType)
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/dial' -Method Post -Body $DialString -Retries $Retries -ErrorAction Stop
        $ThisOutput = $ThisOutput.Status
      }
      Catch
      {
        Write-Error -Message "Couldn't start call to $ThisDestination on $ThisIPv4Address. Could not connect to phone."
        Continue
      }

      if($ThisOutput.IsSuccess -eq $true)
      {
        if($PassThru -eq $true) 
        {
          Start-Sleep -Seconds 1
          $ThisCall = Get-UcsRestCallStatus -IPv4Address $IPv4Address
          $null = $OutputArray.Add($ThisCall)
        }
      }
      else 
      {
        Write-Error -Message "Couldn't start call to $ThisDestination on $ThisIPv4Address. An error was returned from the phone."
        Continue
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Stop-UcsRestCall 
{
  <#
      .SYNOPSIS
      Stop a phone call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER CallHandle
      Manually specify the callhandle to end.

      .PARAMETER Force
      Skip firmware version check. On certain firmware versions, calling Stop-UcsRestCall may cause the REST API to stop responding.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries,
    [Switch]$Force)
    
  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address) 
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        if($CallHandle -notmatch '^0x[a-f0-9]{7,8}$') 
        {
          #This section attempts to get a call handle if one was not provided.
          if($CallHandle.Length -gt 0)
          {
            Write-Error -Message "Invalid call handle $CallHandle provided for $ThisIPv4Address."
          }
          else
          {
            Try
            {
              $CallStatus = Get-UcsRestCall -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $CallHandle = $CallStatus.CallHandle
            }
            Catch
            {
              Write-Error -Message "Couldn't get call handle for $ThisIPv4Address."
              Continue
            }
          }
        }

        if($CallHandle.Length -gt 0) 
        {
          #This section only starts if we have a callhandle.
          if($Force -ne $true)
          {
            #In certain 5.5.2 releases (5.5.2.8571 on VVX 310/311 tested), using the endCall endpoint causes a failure in the REST API.
            $DeviceInfo = Get-UcsRestDeviceInfo -IPv4Address $ThisIPv4Address
            if($DeviceInfo.FirmwareRelease -like '5.5.2.*')
            {
              Write-Error ('{0} is running firmware {1} which has a known issue with Stop-UcsRestCall. Use another API or use the Force parameter.' -f $ThisIPv4Address,$DeviceInfo.FirmwareRelease)
              Continue
            }
          } 
          else
          {
            #Trying to be clear at the expense of technical accuracy.
            Write-Warning "Force was specified to end the call on $ThisIPv4Address. On some phones, ending a call with Force may cause the REST API to stop responding until the next reboot."
          }
        
          $CallHandle = Get-UcsCleanJSON -String $CallHandle

          $CallEndString = ('{{"data":{{"Ref": "{0}"}}}}' -f $CallHandle)
          Try
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/endCall' -Body $CallEndString -Method Post -Retries $Retries -ErrorAction Stop
          }
          Catch
          {
            Write-Debug -Message "Caught error $_."
            Write-Error -Message "Couldn't end call $CallHandle for $ThisIPv4Address."
            Continue
          }
          $null = $OutputArray.Add($ThisOutput.Status)
        }
        else 
        {
          Write-Warning -Message ('No call to end for {0}.' -f $ThisIPv4Address)
        }
      }
    }
  } END {
    Return $OutputArray
  }
}

