Remove-Item -Path datas\* -Force

go build -o datagenerator.exe datagenerator/datagenerator.go

.\datagenerator.exe -files=2 -rows=50000 -outdir datas -prefix data

.\datagenerator.exe -files=20 -rows=50000 -outdir datas -prefix data

# --------------------------------------

go build -o http-server.exe http/server/http-server.go

.\http-server.exe -port 8080

# --------------------------------------

go build -o http-client.exe http/client/http-client.go

.\http-client.exe -baseurl="http://localhost:8080" -datadir="datas" -pattern="*.txt"

# --------------------------------------

go build -o blob-set-tags.exe blob/set-tags/blob-set-tags.go

# $account = "myaccount"
# $accountKey = "..."

.\blob-set-tags.exe -account="$account" -key="$accountKey" -container="$container" -datadir="datas2" -pattern="*.txt"

# --------------------------------------

Set-Location blob/create-blobs/
go build -o ../../blob-create-blobs.exe blob-create-blobs.go

# $account = "myaccount"
# $accountKey = "..."
# $container = "..."

Set-Location ../..
.\blob-create-blobs.exe -account="$account" -key="$accountKey" -container="$container" -indir=datas

# --------------------------------------

Set-Location StorageApp

dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true /p:TrimUnusedDependencies=true
Copy-Item bin\Release\net9.0\win-x64\publish\StorageApp.exe ..

Set-Location ..

.\StorageApp.exe
