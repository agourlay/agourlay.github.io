+++
title = "New Key-Value Store in Rust at Qdrant"
description = "Introducing Gridstore: Qdrant's Custom Key-Value Store"
date = 2025-02-10
[taxonomies]
tags=["Rust", "Qdrant", "storage"]
+++

I have been working at [Qdrant](https://github.com/qdrant/qdrant) for a while now, where I get the opportunity to work on very interesting problems.

This article is an [external publication](https://qdrant.tech/articles/gridstore-key-value-storage/) regarding my latest contributions on a new key-value storage engine specialized for our needs.

The storage is not yet available as a standalone crate for the moment; in the meantime, there are a few pointers to get started reading the code for the curious.

- the gridstore code [internal crate](https://github.com/qdrant/qdrant/tree/dev/lib/gridstore)
- usage for [payload storage](https://github.com/qdrant/qdrant/blob/dev/lib/segment/src/payload_storage/mmap_payload_storage.rs)
- usage for [sparse vector storage](https://github.com/qdrant/qdrant/blob/dev/lib/segment/src/vector_storage/sparse/mmap_sparse_vector_storage.rs)

