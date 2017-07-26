#requires -Version 3.0

$Script:PolycomMACPrefixes = ('0004f2', '64167F')

Function Start-UcsCall
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A call destination, such as ''+15555555555@example.com or johnsmith@example.com''')][String]$Destination,
    [Int][ValidateRange(1,24)]$LineId = 1,
    [String][ValidateSet('SIP')]$CallType = 'SIP',
    [Switch]$PassThru)
  
  Begin
  {
    $OutputObject = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $ThisOutput = Start-UcsRestCall -IPv4Address $ThisIPv4Address -Destination $Destination -LineId $LineId -PassThru:$PassThru -ErrorAction Stop
              $GetSuccess = $true
            }
            'Push'
            {
              $ThisOutput = Start-UcsPushCall -IPv4Address $ThisIPv4Address -Destination $Destination -LineId $LineId -PassThru:$PassThru -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisOutput = $ThisOutput | Select-Object -ExcludeProperty API -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }
          $null = $ThisOutput | ForEach-Object -Process {
            $OutputObject.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get call info for {0}.' -f $ThisIPv4Address)
      }
    }
  }
  End
  {
    if($PassThru -eq $true)
    {
      Return $OutputObject
    }
  }
}

Function Stop-UcsCall
{
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle)
  
  Begin
  {
    $OutputObject = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        Foreach($Protocol in $ThisProtocolPriority)
        {
          Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
          Try
          {
            Switch($Protocol)
            {
              'REST'
              {
                if($CallHandle)
                {
                  $ThisOutput = Stop-UcsRestCall -IPv4Address $ThisIPv4Address -CallHandle $CallHandle -ErrorAction Stop -Confirm:$false
                }
                else
                {
                  $ThisOutput = Stop-UcsRestCall -IPv4Address $ThisIPv4Address -ErrorAction Stop -Confirm:$false
                }
                $GetSuccess = $true
              }
              'Push'
              {
                if($CallHandle)
                {
                  $ThisOutput = Send-UcsPushCallAction -IPv4Address $ThisIPv4Address -CallAction EndCall -CallHandle $CallHandle -ErrorAction Stop -Confirm:$false
                }
                else
                {
                  $ThisOutput = Send-UcsPushCallAction -IPv4Address $ThisIPv4Address -CallAction EndCall -ErrorAction Stop -Confirm:$false
                }
                $GetSuccess = $true
              }
              Default
              {
                Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
              }
            }
          }
          Catch 
          {
            Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
          }
        
          if($GetSuccess)
          {
            Break #Get out of the protocol loop once we succeed.
          }
        }
      
        if($GetSuccess -eq $false) 
        {
          Write-Error -Message ('Could not get call info for {0}.' -f $ThisIPv4Address)
        }
      }
    }
  }
  End
  {
    Return $OutputObject
  }
}

Function Get-UcsPhoneInfo 
{
  <#
      .SYNOPSIS
      Retrieves most commonly used phone data.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Describe parameter -Quiet.

      .EXAMPLE
      Get-SummaryPhoneData -IPv4Address Value -Quiet
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-SummaryPhoneData

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = $Script:DefaultRetries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        $Success = $true
        $Model = $null
        $FirmwareRelease = $null
        $LastReboot = $null
        $MacAddress = $null
        $Registered = $null
        $SipAddress = $null
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $DeviceInfo = Get-UcsRestDeviceInfo -IPv4Address $ThisIPv4Address -Quiet -ErrorAction Stop
              $LineInfo = Get-UcsRestLineInfo -IPv4Address $ThisIPv4Address -Quiet -ErrorAction Stop

              $Model = $DeviceInfo.Model
              $FirmwareRelease = $DeviceInfo.FirmwareRelease
              $LastReboot = $DeviceInfo.LastReboot
              $MacAddress = $DeviceInfo.MacAddress
              $Registered = $LineInfo.Registered
              $SipAddress = $LineInfo.SipAddress
            }
            'Web'
            {
              $PhoneInfo = Get-UcsWebDeviceInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $SignInInfo = Get-UcsWebLyncSignIn -IPv4Address $ThisIPv4Address -ErrorAction Stop
          
              $Model = $PhoneInfo.Model
              $FirmwareRelease = $PhoneInfo.FirmwareRelease
              $MacAddress = $PhoneInfo.MacAddress
              $Registered = $SignInInfo.Registered
              $SipAddress = $SignInInfo.SipAddress
              $LastReboot = $PhoneInfo.LastReboot
            }
            'SIP'
            {
              $PhoneInfo = Get-UcsSipPhoneInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
          
              $Model = $PhoneInfo.Model
              $FirmwareRelease = $PhoneInfo.FirmwareRelease
              $MacAddress = $PhoneInfo.MacAddress
              $Registered = $PhoneInfo.Registered
              $SipAddress = $PhoneInfo.SipAddress
              $LastReboot = $null
            }
            'Poll'
            {
              $PhoneInfo = Get-UcsPollDeviceInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              
              $Model = $PhoneInfo.Model
              $FirmwareRelease = $PhoneInfo.FirmwareRelease
              $MacAddress = $PhoneInfo.MacAddress
              $SipAddress = $PhoneInfo.SipAddress
              if($SipAddress.length -gt 0) 
              {
                $Registered = $true
              }
              else 
              {
                $Registered = $false
              }
              $LastReboot = $null
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for PhoneInfo.' -f $Protocol)
              $Success = $false
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0} via {1}. '{2}'" -f $ThisIPv4Address, $Protocol, $_)
          $Success = $false
        }
        
        if($Success -eq $true) 
        {
          Break
        }
      }

      if($Success -eq $false) 
      {
        #All protocols have failed.
        Write-Error -Message ('Could not connect to {0}.' -f $ThisIPv4Address)
        Continue
      }

      $OutputObject = $ThisIPv4Address | Select-Object -Property @{
        Name       = 'IPv4Address'
        Expression = {
          $ThisIPv4Address
        }
      }, @{
        Name       = 'Model'
        Expression = {
          $Model
        }
      }, @{
        Name       = 'FirmwareRelease'
        Expression = {
          $FirmwareRelease
        }
      }, @{
        Name       = 'LastReboot'
        Expression = {
          $LastReboot
        }
      }, @{
        Name       = 'MACAddress'
        Expression = {
          $MacAddress
        }
      }, @{
        Name       = 'Registered'
        Expression = {
          $Registered
        }
      }, @{
        Name       = 'SIPAddress'
        Expression = {
          $SipAddress
        }
      }, @{
        Name       = 'API'
        Expression = {
          $Protocol
        }
      }

      $null = $OutputArray.Add($OutputObject)
    }
  } END {
    Return $OutputArray
  }
}

Function Restart-UcsPhone 
{
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [String][ValidateSet('Reboot','Restart')]$Type = 'Reboot',
  [Switch]$PassThru)
  
  #Specifying type of reboot is only possible using the web UI. All other methods cause a full reboot.
  #Also, it's only possible to reboot with SIP if a specific setting is configured.
  
  BEGIN
  {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
    
    if($Type -eq 'Restart') 
    {
      Write-Verbose -Message 'Protocol priority temporarily overridden, as a restart is only possible with Web.'
      $ThisProtocolPriority = ('Web') #A restart is only possible using the web UI at this time.
    }
    else 
    {
      $ThisProtocolPriority = Get-UcsConfigPriority
    }
  }
  PROCESS
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
      {
        $WhatIf = $false
      }
      else 
      {
        $WhatIf = $true
      }
    
      $RebootSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('Trying {0} {2} for {1}.' -f $Protocol, $ThisIPv4Address, $Type.ToLower())
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $null = Restart-UcsRestPhone -IPv4Address $ThisIPv4Address -ErrorAction Stop -Confirm:$false -WhatIf:$WhatIf
              $RebootSuccess = $true
            }
            'Web'
            {
              $null = Restart-UcsWebPhone -IPv4Address $ThisIPv4Address -Type $Type -ErrorAction Stop -Confirm:$false -WhatIf:$WhatIf
              $RebootSuccess = $true
            }
            'SIP'
            {
              Write-Debug -Message ('Starting check-sync reboot for {0}. If it does not work, ensure that configuration allows this type of reboot.' -f $ThisIPv4Address)
              $null = Restart-UcsSipPhone -IPv4Address $ThisIPv4Address -ErrorAction Stop -Confirm:$false -WhatIf:$WhatIf
              $RebootSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the {1} operation.' -f $Protocol, $Type)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($RebootSuccess -eq $true) 
        {
          Break #Get out of the loop once we succeed.
        }
      }
      
      if($RebootSuccess -eq $false) 
      {
        Write-Error -Message ('Could not {0} {1}.' -f $Type, $ThisIPv4Address)
      }
    }
  }
  END
  {
    if($PassThru -eq $true) 
    {
      Return $StatusResult
    }
  }
}

Function Get-UcsParameter 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A UCS parameter, such as "Up.Timeout."',ValueFromPipelineByPropertyName,ParameterSetName = 'Parameter')][String[]]$Parameter,
    [Parameter(ParameterSetName = 'All')][Switch]$All,
  [Switch]$PassThru)
  
  BEGIN
  {
    $ParameterResult = New-Object -TypeName System.Collections.ArrayList
    
    if($PSCmdlet.ParameterSetName -eq 'All')
    {
      $ThisProtocolPriority = ('Web')
    }
    else
    {
      $ThisProtocolPriority = Get-UcsConfigPriority
    }
  }
  PROCESS
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('Trying {0} {2} for {1}.' -f $Protocol, $ThisIPv4Address, $PSCmdlet.ParameterSetName)
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $ThisParameter = Get-UcsRestParameter -IPv4Address $ThisIPv4Address -Parameter $Parameter -ErrorAction Stop
              $GetSuccess = $true
            }
            'Web'
            {
              if($PSCmdlet.ParameterSetName -eq 'All')
              {
                $ThisParameter = Get-UcsWebConfiguration -IPv4Address $ThisIPv4Address -ErrorAction Stop
              }
              else 
              {
                $ThisParameter = Get-UcsWebParameter -IPv4Address $ThisIPv4Address -Parameter $Parameter -ErrorAction Stop
              }
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisParameter = $ThisParameter | Select-Object -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }
          $null = $ThisParameter | ForEach-Object -Process {
            $ParameterResult.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get parameter for {0}.' -f $ThisIPv4Address)
      }
    }
  }
  END
  {
    Return $ParameterResult
  }
}

Function Get-UcsProvisioningInfo 
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )
  
  Begin
  {
    $OutputObject = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $ThisProvisioning = Get-UcsRestNetworkInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            'Web'
            {
              $ThisProvisioning = Get-UcsWebProvisioningInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisProvisioning = $ThisProvisioning | Select-Object -Property ProvServerAddress, ProvServerUser, ProvServerType, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }, Ipv4Address
          $null = $ThisProvisioning | ForEach-Object -Process {
            $OutputObject.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get provisioning info for {0}.' -f $ThisIPv4Address)
      }
    }
  }
  End
  {
    Return $OutputObject
  }
}

Function Get-UcsNetworkInfo 
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )
  
  Begin
  {
    $OutputObject = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $ThisOutput = Get-UcsRestNetworkInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            'Poll'
            {
              $ThisOutput = Get-UcsPollNetworkInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisOutput = $ThisOutput | Select-Object -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }
          $null = $ThisOutput | ForEach-Object -Process {
            $OutputObject.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get network info for {0}.' -f $ThisIPv4Address)
      }
    }
  }
  End
  {
    Return $OutputObject
  }
}
Function Get-UcsCall
{
  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )
  
  Begin
  {
    $OutputObject = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'REST'
            {
              $ThisOutput = Get-UcsRestCall -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            'Poll'
            {
              $ThisOutput = Get-UcsPollCall -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisOutput = $ThisOutput | Select-Object -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }
          $null = $ThisOutput | ForEach-Object -Process {
            $OutputObject.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get call info for {0}.' -f $ThisIPv4Address)
      }
    }
  }
  End
  {
    Return $OutputObject
  }
}


Function Find-UcsPhoneByDHCP 
{
  #Requires -modules ActiveDirectory,DhcpServer
  <#
      .SYNOPSIS
      Uses DHCP to find all phones in the current environment. Requires DHCP and AD powershell modules.

      .DESCRIPTION
      Uses the DHCP cmdlets to enumerate all DHCP scopes, then checks each scope for leases assigned to Polycom-prefixed MAC addresses. It requires the DHCP and AD Powershell modules to operate.

      .EXAMPLE
      Find-PhoneByDHCP
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Find-PhoneByDHCP

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
      
  #>
  $Domain = (Get-ADDomain).DistinguishedName
  $DHCPServers = Get-ADObject -SearchBase ('cn=configuration,{0}' -f $Domain) -Filter "objectclass -eq 'dhcpclass' -AND Name -ne 'dhcproot'"

  Foreach ($DHCPServer in $DHCPServers) 
  {
    if(Test-Connection -ComputerName $DHCPServer.Name -Count 1 -Quiet) 
    {
      Try 
      {
        $Scopes = $null
        $Leases = $null
        $Scopes = Get-DhcpServerv4Scope -ComputerName ($DHCPServer.Name) -ErrorAction SilentlyContinue
        $Leases = $Scopes | ForEach-Object -Process {
          Get-DhcpServerv4Lease -ComputerName ($DHCPServer.Name) -ScopeId $_.ScopeId -ErrorAction SilentlyContinue
        }
      }
      Catch 
      {
        Write-Warning -Message ("Couldn't use {0} as a DHCP server. {1}" -f $DHCPServer.Name, $_)
      }
      
      $Leases = $Leases | Select-Object -Property @{
        Name       = 'IPv4Address'
        Expression = {
          $_.IpAddress.IpAddressToString
        }
      }, @{
        Name       = 'MacAddress'
        Expression = {
          $_.ClientId.Replace('-', '')
        }
      }

      $DiscoveredDhcpPhones += $Leases |
      Where-Object -FilterScript {
        $_.MacAddress.length -eq 12
      } |
      Where-Object -FilterScript {
        $_.MacAddress.substring(0,6) -in $PolycomMACPrefixes
      }
    }
  }

  <#
      $PolycomPhones = New-Object -TypeName System.Collections.ArrayList
      Foreach ($Client in $DiscoveredDhcpPhones) 
      {
      $null = $PolycomPhones.Add($Client)
      #TODO: Maybe add some logic to check when multiple devices claim the same MAC and see which IP, if any, is responding.
      }

      $PolycomPhones = $PolycomPhones |
      Sort-Object -Property IPv4Address -Unique
  #>
  
  $PolycomPhones = $DiscoveredDhcpPhones | Sort-Object -Property IPv4Address -Unique

  Return $PolycomPhones
}

Function Get-UcsCallLog 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  
  Begin
  {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try 
      {
        $PhoneInfo = Get-UcsPhoneInfo -IPv4Address $ThisIPv4Address -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message ("Couldn't get call information for {0}. Unable to connect to phone." -f $ThisIPv4Address)
        Continue
      }
      
      if($PhoneInfo.MacAddress -notmatch '^[a-f0-9]{12}$')
      {
        Write-Error -Message ("Couldn't get call information for {0}. Unable to get MAC address." -f $ThisIPv4Address)
        Continue
      }
      
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'Provisioning'
            {
              $ThisCallLog = Get-UcsProvCallLog -MacAddress $PhoneInfo.MacAddress -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $ThisCallLog = $ThisCallLog | Select-Object -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }
          $null = $ThisCallLog | ForEach-Object -Process {
            $AllCalls.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get provisioning info for {0}.' -f $ThisIPv4Address)
        Continue
      }
    }
  }
  End
  {
  
    Return $AllCalls
  }
}
Function Get-UcsLog 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(Mandatory)][ValidateSet('app','boot')][String]$LogType)
  
  Begin
  {
    $AllLogs = New-Object -TypeName System.Collections.ArrayList
    $ThisProtocolPriority = Get-UcsConfigPriority
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $GetSuccess = $false
      
      Foreach($Protocol in $ThisProtocolPriority)
      {
        Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $Protocol, $ThisIPv4Address,$PSCmdlet.MyInvocation.MyCommand.Name)
        Try
        {
          Switch($Protocol)
          {
            'Provisioning'
            {
              $MacAddress = Get-UcsPhoneInfo -IPv4Address $IPv4Address -ErrorAction Stop | Select-Object -ExpandProperty MacAddress -ErrorAction Stop
              $Logs = Get-UcsProvLog -MacAddress $MacAddress -LogType $LogType -ErrorAction Stop
              $Logs = $Logs | Select-Object -Property *, @{
                Name       = 'IPv4Address'
                Expression = {
                  $ThisIPv4Address
                }
              }
              $GetSuccess = $true
            }
            'Web'
            {
              $Logs = Get-UcsWebLog -IPv4Address $IPv4Address -LogType $LogType -ErrorAction Stop
              $GetSuccess = $true
            }
            Default
            {
              Write-Debug -Message ('Protocol {0} is not supported for the operation.' -f $Protocol)
            }
          }
        }
        Catch 
        {
          Write-Debug -Message ("Encountered an error on {0}. '{1}'" -f $ThisIPv4Address, $_)
        }
        
        if($GetSuccess -eq $true) 
        {
          $Logs = $Logs | Select-Object -Property *, @{
            Name       = 'API'
            Expression = {
              $Protocol
            }
          }
          $null = $Logs | ForEach-Object -Process {
            $AllLogs.Add($_)
          }
          Break #Get out of the protocol loop once we succeed.
        }
      }
      
      if($GetSuccess -eq $false) 
      {
        Write-Error -Message ('Could not get log info for {0}.' -f $ThisIPv4Address)
        Continue
      }
    }
  }
  End
  {
  
    Return $AllLogs
  }
}

Function Test-UcsAPI
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  
  Begin
  {
    $ResultArray = New-Object -TypeName Collections.ArrayList
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      #REST
      $REST = Get-UcsRestDeviceInfo -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
      if($REST.MACAddress -match '[a-f0-9]{12}')
      {
        $RESTStatus = $true
      }
      else
      {
        $RESTStatus = $false
      }
      
      #Web
      $Web = Get-UcsWebDeviceInfo -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
      if($Web.MACAddress -match '[a-f0-9]{12}')
      {
        $WebStatus = $true
      }
      else
      {
        $WebStatus = $false
      }
      
      #Poll
      $Poll = Get-UcsPollDeviceInfo -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
      if($Poll.MACAddress -match '[a-f0-9]{12}')
      {
        $PollStatus = $true
      }
      else
      {
        $PollStatus = $false
      }
      
      #Provisioning
      $Provisioning = Get-UcsCallLog -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
      if($Provisioning.count -gt 0)
      {
        $ProvisioningStatus = $true
      }
      else
      {
        $ProvisioningStatus = $false
      }
      
      #Push
      Try
      {
        $null = Send-UcsPushKeyPress -IPv4Address $ThisIPv4Address -Key ('Home') -ErrorAction Stop -WarningAction SilentlyContinue -Confirm:$false
        $PushStatus = $true
      }
      Catch
      {
        $PushStatus = $false
      }
      #$PushStatus = $null #This detection doesn't work.
      
      #SIP
      $SIP = Get-UcsSipPhoneInfo -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
      if($SIP.FirmwareRelease.Length -ge 1)
      {
        $SIPStatus = $true
      }
      else
      {
        $SIPStatus = $false
      }
      
      $ThisStatusResult = 1 | Select-Object -Property @{
        Name       = 'REST'
        Expression = {
          $RESTStatus
        }
      }, @{
        Name       = 'Poll'
        Expression = {
          $PollStatus
        }
      }, @{
        Name       = 'Provisioning'
        Expression = {
          $ProvisioningStatus
        }
      }, @{
        Name       = 'Push'
        Expression = {
          $PushStatus
        }
      }, @{
        Name       = 'SIP'
        Expression = {
          $SIPStatus
        }
      }, @{
        Name       = 'Web'
        Expression = {
          $WebStatus
        }
      }, @{
        Name       = 'IPv4Address'
        Expression = {
          $ThisIPv4Address
        }
      }
      $null = $ResultArray.Add($ThisStatusResult)
    }
  }
  End
  {
    Return $ResultArray
  }
}
