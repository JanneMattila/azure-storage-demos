# Notes

VM SKU: B4ms

100k run:

```
Export completed. Total blobs: 100001, Total files: 2
Total batches: 21, Average batch time: 0.64 seconds
Total run time: 0.23 minutes
Final throughput: 7391.59 blobs/second
Extrapolated time for 1 billion blobs: 37.58 hours
```

Size 8.67 MB

---

500k run:

```
Exported 84679 blobs to file 5
Export completed. Total blobs: 484679, Total files: 5
Total batches: 97, Average batch time: 0.59 seconds
Total run time: 0.97 minutes
Final throughput: 8346.02 blobs/second
Extrapolated time for 1 billion blobs: 33.28 hours
```

Size 42 MB

---

700k run:

```
Export completed. Total blobs: 710983, Total files: 8
Total batches: 143, Average batch time: 0.55 seconds
Total run time: 1.33 minutes
Final throughput: 8904.54 blobs/second
Extrapolated time for 1 billion blobs: 31.20 hours
```

Size 61.7 MB

---

1.1 M run:

```
Export completed. Total blobs: 1100001, Total files: 12
Total batches: 221, Average batch time: 0.64 seconds
Total run time: 2.38 minutes
Final throughput: 7701.31 blobs/second
Extrapolated time for 1 billion blobs: 36.07 hours
```

Size 96.7 MB

---

After file writing is in the seperate thread.

~700k run:

```
Export completed. Total blobs: 682761, Total files: 7
Total batches: 140, Average batch time: 0.60 seconds
Total run time: 1.42 minutes
Final throughput: 8012.65 blobs/second
Extrapolated time for 1 billion blobs: 34.67 hours
```

Size 59.2 MB

---

~600k run:

```
Export completed. Total blobs: 592761, Total files: 1
Total batches: 122, Average batch time: 0.50 seconds
Total run time: 1.04 minutes
Final throughput: 9500.05 blobs/second
Extrapolated time for 1 billion blobs: 29.24 hours
```

51.4 MB

---

VM SKU: B8ms

