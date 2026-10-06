[CmdletBinding()]
param([string]$VendorGitDirectory,[string]$CacheRoot=(Join-Path $PSScriptRoot '..\build\upstream\pslowering'),[switch]$Acquire,[switch]$Help)
$ErrorActionPreference='Stop'
$commit='26fe7a864b19e70cfd6937ab062335a05fac3232'
$digest='7005315D32BD1A786EE601B2A57A847581E85A764B7CE9815C19146906E952A5'
$cache=[IO.Path]::GetFullPath($CacheRoot)
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryPrefix=$repository.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
if(-not $cache.StartsWith($repositoryPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Compiler acquisition/cache must remain inside this repository.'}
if($Help -or -not $Acquire){
    $archivePath=Join-Path $cache 'source.tar'
    $status=if(-not(Test-Path -LiteralPath $archivePath)){'Not acquired'}elseif((Get-FileHash -LiteralPath $archivePath).Hash -ceq $digest){'Verified'}else{'Integrity mismatch'}
    [pscustomobject]@{CompilerCommit=$commit;ArchiveStatus=$status;Usage='Acquire-PSLowering.ps1 -Acquire [-VendorGitDirectory <bare mirror>] [-CacheRoot <repository cache>]'}
    return
}
$null=[IO.Directory]::CreateDirectory($cache)
if($VendorGitDirectory){
    $VendorGitDirectory=[IO.Path]::GetFullPath($VendorGitDirectory)
    $vendorPrefix=[IO.Path]::GetFullPath((Join-Path (Split-Path $repository) '.vendor')).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $VendorGitDirectory.StartsWith($repositoryPrefix,[StringComparison]::OrdinalIgnoreCase) -and -not $VendorGitDirectory.StartsWith($vendorPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Use this repository cache or a pinned shared vendor mirror, never another project checkout.'}
}
if(-not $VendorGitDirectory){
    $VendorGitDirectory=Join-Path (Split-Path $cache) 'pslowering.git'
    if(-not (Test-Path -LiteralPath $VendorGitDirectory)){
        & git clone --bare https://github.com/MansfieldPlumbing/PSLowering.git $VendorGitDirectory
        if($LASTEXITCODE){throw 'PSLowering acquisition failed.'}
    }
}
& git --git-dir=$VendorGitDirectory cat-file -e "$commit^{commit}"
if($LASTEXITCODE){throw 'Pinned upstream commit unavailable.'}
$archive=Join-Path $cache 'source.tar'
& git --git-dir=$VendorGitDirectory archive --format=tar --output=$archive $commit
if($LASTEXITCODE){throw 'Pinned source export failed.'}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $digest){throw 'Pinned archive integrity check failed.'}
& tar -xf $archive -C $cache
if($LASTEXITCODE){throw 'Verified archive extraction failed.'}
'PASS: pinned PSLowering archive SHA-256 verified before use.'
