GROOVY (To Get All Available Branches):
import jenkins.model.*

credentialsId = 'GitCredentials'

def creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
  com.cloudbees.plugins.credentials.common.StandardUsernameCredentials.class, Jenkins.instance, null, null ).find{
    it.id == credentialsId}


def gitBranches = "git ls-remote --heads http://${creds.username}:${creds.password}${BranchChecker}".execute().text.readLines().collect {
    def branchName = it.split()[1].replaceAll("refs/heads/", "")
    // Check if the branch name contains "/"
    if (branchName.contains("/")) {
        // If it contains "/", assign a high value to sort it at the end
        branchName = "zzz_${branchName}"
    }
    branchName
}.sort()

// Remove the "zzz_" prefix from branch names for display purposes
gitBranches = gitBranches.collect { it.startsWith("zzz_") ? it.substring(4) : it }

return gitBranches





POWERSHELL:

##Variables Start
$RepoName = ("${ENV:GitURL}" -split '/' | Select-Object -Last 1) -replace '\.git$'
$CompressionSuffix = ".zip"
##Variables End
  
##Checks if Git is installed, and install it if necessary
if (-not (Test-Path -Path "C:\Program Files\Git\bin\git.exe")) {
  # Git is not installed, attempt to install
  Write-Host "Git is not installed. Installing..."
  Start-Process -Wait -FilePath "https://git-scm.com/download/win" -ArgumentList "/SILENT"
  Write-Host "Git installed successfully."
}

#Add git credentials to the Windows Credential Manager
$repoUrl = "git:http://" + ("${ENV:GitURL}" -replace '^https?://|/.*$')
cmdkey /delete:$repoUrl  
##Uses Jenkins Credentials for GitUser and GitPass
cmdkey /generic:$repoUrl /user:"${ENV:GitUser}" /pass:"${ENV:GitPass}" 
      
##Checks if the repository exists locally, and clone it if necessary
cd "${ENV:WORKSPACE}"
if(-not (Test-Path -Path "${ENV:WORKSPACE}/$RepoName")){
  Write-Host "Cloning the Git repository..."
  git clone "${ENV:GitURL}"
  Write-Host "Cloned the Git repository from ${ENV:GitURL} to ${ENV:WORKSPACE}/$RepoName"
}

##Checks out and pulls the specified repository branch
cd "$RepoName"
Write-Host "Checking-out the repository branch..."
git pull
git reset --hard
git checkout "${ENV:Branch}"
git pull
Write-Host "Checked-out the ${ENV:Branch} branch from the repository to ${ENV:WORKSPACE}/$RepoName"
  
##Builds the directory for the Build
cd "${ENV:Unity}"
if(Test-Path -Path "${ENV:LocalBuildPath}/"){
  Remove-Item -Recurse -force "${ENV:LocalBuildPath}/*"
} else{
  New-Item -ItemType Directory -Path "${ENV:LocalBuildPath}/"
  Write-Host "Created the Build Path Directory"
}

##Builds the Unity Project, waits and stores the built project name
Write-Host "Building Unity project"
Start-Process powershell.exe -Wait -ArgumentList "-Command", "cd '${ENV:Unity}'; .\Unity.exe -projectPath '${ENV:WORKSPACE}/$RepoName' -batchmode -executeMethod Builder.Build -BuildLocation `${ENV:LocalBuildPath} -BuildType `${ENV:VersionType} -JenkinsBuildNumber `${ENV:BUILD_NUMBER}"

Write-Host "Unity project built to ${ENV:LocalBuildPath}"
$BuildFolderPath = (Get-ChildItem -Path ${ENV:LocalBuildPath} -Directory)[0].FullName
$BuildZipName = ($BuildFolderPath -split "\\")[-1] + $CompressionSuffix
  
##Update the Version Number
if(${ENV:VersionType} -ne "None"){
    cd "${ENV:WORKSPACE}/$RepoName"
    git add .
    git commit -m "New Jenkins Build - Version Update"
    git push
}

##Checks if 7-Zip is installed, and installs it if necessary
$7ZipPath = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $7ZipPath)) {
  Write-Host "7-Zip is not installed. Installing..."
  Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z1900-x64.exe" -OutFile "$env:TEMP\7z.exe" -UseBasicParsing
  Start-Process -Wait -FilePath "$env:TEMP\7z.exe" -ArgumentList "/S"
  Write-Host "Installed 7-Zip"
}

##Compress the build into a .zip file
  $7ZipArgs = "a -tzip -mx5 -mmt -r -bb0 ""${ENV:LocalBuildPath}$BuildZipName"" ""$BuildFolderPath\*"""
  Write-Host "Build is being compressed..."
  Start-Process -FilePath $7ZipPath -ArgumentList $7ZipArgs -Wait -NoNewWindow
  Write-Host "Build has been compressed to ${ENV:LocalBuildPath}$BuildZipName"

##Installs WinSCP if required
$WinSCPPath = "C:\Program Files (x86)\WinSCP"
if (!(Test-Path "$WinSCPPath\WinSCP.exe")) {
	Write-Host "Installing Win SCP"
    ##Download WinSCP installer
	Start-Process -Wait -FilePath "curl.exe" -ArgumentList "-s -o ${ENV:WORKSPACE}WinSCP.exe https://winscp.net/download/files/202404111235d9b56e62f2186a194ce233044bda2cdb/WinSCP-6.3.2-Setup.exe"
    ##Install WinSCP
	Start-Process -Wait -FilePath "${ENV:WORKSPACE}WinSCP.exe" -ArgumentList "/VERYSILENT /ALLUSERS"
    ##Remove WinSCP installer
	Remove-Item "${ENV:WORKSPACE}WinSCP.exe"
}

cd $WinSCPPath
##Load WinSCP .NET assembly
Add-Type -Path "WinSCPnet.dll"

##Setup remote session options
Write-Host "Connecting to Remote Server"
##Uses Jenkins Credentials for FTPUser and FTPPass
$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
  Protocol = [WinSCP.Protocol]::Ftp
  HostName = ${ENV:ServerAddress}
  UserName = ${ENV:FTPUser}
  Password = ${ENV:FTPPass}
}

##Open new remote session
$session = New-Object WinSCP.Session
$session.Open($sessionOptions)    
  
Write-Host "Uploading build"
##Transfer the backup to the remote server
$t1 = "${ENV:LocalBuildPath}$BuildZipName"
$t2 = "/${ENV:RemotePath}${ENV:BuildFolder}$BuildZipName"
$transferResult = $session.PutFiles($t1, $t2)
  
if($transferResult.IsSuccess){
  Write-Host "Successfully uploaded build to ${ENV:RemotePath}${ENV:BuildFolder}$BuildZipName"
}
else{
  Write-Host "Failed to upload build to ${ENV:RemotePath}${ENV:BuildFolder}$BuildZipName"
}

$session.Dispose()

exit
  
  
  
##Deprecated Code
cd $WinSCPPath

##Uploads the files and disposes of the webclient access
##Uses Jenkins Credentials for FTPUser and FTPPass
@"
open ftp://${ENV:FTPUser}:${ENV:FTPPass}@${ServerAddress}
put "${ENV:LocalBuildPath}${BuildZipName}" "${ENV:RemotePath}${ENV:BuildPath}${BuildZipName}"
bye
"@ | Set-Content -Path ${ENV:WORKSPACE}command.txt -Force

.\"WinSCP.com" /script="${ENV:WORKSPACE}command.txt"
Remove-Item ${ENV:WORKSPACE}command.txt -Force