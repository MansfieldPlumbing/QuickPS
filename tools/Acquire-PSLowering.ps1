[CmdletBinding()]
param([string]$VendorGitDirectory,[string]$CacheRoot=(Join-Path $PSScriptRoot '..\build\upstream\pslowering'))
$ErrorActionPreference='Stop'
$commit='26fe7a864b19e70cfd6937ab062335a05fac3232'
$digest='7005315D32BD1A786EE601B2A57A847581E85A764B7CE9815C19146906E952A5'
$cache=[IO.Path]::GetFullPath($CacheRoot)
$null=[IO.Directory]::CreateDirectory($cache)
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
