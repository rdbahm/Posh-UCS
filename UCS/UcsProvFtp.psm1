$Script:Credential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ('PlcmSpIp', (ConvertTo-SecureString -String 'PlcmSpIp' -AsPlainText -Force)))

Function Set-UcsProvFTPAPICredential
{
  Param([Parameter(Mandatory)][PsCredential[]]$Credential)
  
  $Script:Credential = $Credential
}

Function Get-UcsProvFTPAPICredential
{
  Param([String]$Username = $null)
  
  if($Username -ne $null)
  {
    Return ($Script:Credential | Where-Object UserName -eq $Username)
  }
  else
  {
    Return $Script:Credential
  }
}