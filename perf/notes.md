# Notes

Perf testing is always tricky. Here are some
numbers with *very* **very** limited testing.
Your mileage *will* vary.

## File upload from VM to SFTP using `sftp` cli

Numbers if using `sftp -B 262000 -R 32 -C -b`:

| Scenario            | Time                                            |
| ------------------- | ----------------------------------------------- |
| 1 x 30 MB           | 1 to 2 seconds                                  |
| 20 x 30 MB (600 MB) | 20 to 25 seconds                                |
| 1 x 300 MB          | 10 to 15 seconds                                |
| 20 x 300 MB (6 GB)  | 2 mins 30s to 4 mins (8 seconds to 12 per file) |
| 1 x 5 GB            | 2 mins 20s to 3 mins                            |

## File upload from VM to SFTP using custom tool

Numbers if using custom tool in [Perf test apps](./perf/src/Perf test apps).

Example output log:

```
Enumerating files from folder /mnt/sftp...
FTP user: <storage>.azureuser
FTP host: <storage>.blob.core.windows.net
Starting 10 threads to upload to e4ef2ae8-0550-4abc-b518-b5ff857dbd68...
0s: Queue: 660, Uploading: 0
2s: Queue: 650, Uploading: 10
<clip />
121s: Queue: 31, Uploading: 10
122s: Queue: 26, Uploading: 10
123s: Queue: 21, Uploading: 10
124s: Queue: 16, Uploading: 10
125s: Queue: 12, Uploading: 10
126s: Queue: 5, Uploading: 10
127s: Queue: 1, Uploading: 9
It took 129 seconds to upload 660 files to folder e4ef2ae8-0550-4abc-b518-b5ff857dbd68
```

Above test is with 20 GB and 660 files with size ~30MB.

Example files:

```
0 -rw-rw-r-- 1 azureuser azureuser 29M Jan 27 12:15 file_1674821756_94_29.bin
0 -rw-rw-r-- 1 azureuser azureuser 29M Jan 27 12:15 file_1674821756_95_29.bin
0 -rw-rw-r-- 1 azureuser azureuser 30M Jan 27 12:15 file_1674821756_96_30.bin
0 -rw-rw-r-- 1 azureuser azureuser 29M Jan 27 12:15 file_1674821756_97_29.bin
0 -rw-rw-r-- 1 azureuser azureuser 30M Jan 27 12:15 file_1674821756_98_30.bin
```
