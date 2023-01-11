# Notes

Perf testing is always tricky. Here are some
numbers with *very* **very** limited testing.
Your mileage *will* vary.

| Scenario            | Time                                            |
| ------------------- | ----------------------------------------------- |
| 1 x 30 MB           | 1 to 2 seconds                                  |
| 20 x 30 MB (600 MB) | 20 to 25 seconds                                |
| 1 x 300 MB          | 10 to 15 seconds                                |
| 20 x 300 MB (6 GB)  | 2 mins 30s to 4 mins (8 seconds to 12 per file) |
| 1 x 5 GB            | 2 mins 20s to 3 mins                            |
