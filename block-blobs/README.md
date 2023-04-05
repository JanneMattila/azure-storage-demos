# BlockBlobs

Metrics view while uploading 256MB x 4000 times to create one large [BlockBlob](https://learn.microsoft.com/en-us/rest/api/storageservices/understanding-block-blobs--append-blobs--and-page-blobs#about-block-blobs) 
file and using [Put Block](https://learn.microsoft.com/en-us/rest/api/storageservices/put-block?tabs=azure-ad) API:

![blob metrics while uploading BlockBlob](https://user-images.githubusercontent.com/2357647/230024864-d251815d-737c-4874-8ff3-39652be0380d.png)

Metrics view after uploading has finished and final [Put Block List](https://learn.microsoft.com/en-us/rest/api/storageservices/put-block-list?tabs=azure-ad) API call is made:

![blob metrics after file upload has finished](https://user-images.githubusercontent.com/2357647/230033211-7041435c-bd8c-477a-9e4f-fdf31bbe7581.png)

Entire upload duration API calls:

![upload duration api calls](https://user-images.githubusercontent.com/2357647/230034278-616c7a15-067c-4f64-bafd-a11c43d6140b.png)

Uploaded file in container:

![file in container](https://user-images.githubusercontent.com/2357647/230034841-bbca006a-d25b-4a05-8888-5cadb4b78831.png)

See [Python upload code](https://github.com/JanneMattila/python-examples/tree/main/azure-storage) example for more details.
