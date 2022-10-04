+++
title = "Brute forcing protected ZIP archives in Rust"
description = "How to brute force the password of protected ZIP archives using Rust"
date = 2022-10-03
[taxonomies]
tags=["Rust", "security", "multithreading", "benchmarking"]
+++

This article explains how to brute force the password of protected ZIP archives using Rust. It is primarily targeted at beginner Rust developers, but it will surely be interesting to a wider audience.

The full code with better error handling and proper command line arguments (CLI) is available at [zip-password-finder](https://github.com/agourlay/zip-password-finder).

## Context

A while back, I found myself in possession of a ZIP archive containing family data that I could not access.
The archive was protected by a password which no one knew.

After a short investigation, I found several tools advertised as being capable of recovering passwords for various types of compressed archives.
However, most of them looked rather fishy or required a license, which made me rather skeptical.

It is at that point that I reached the conclusion that building such a tool myself would be a good learning opportunity.

I might be able to recover the data and it could be the subject of a blog article!

## Architecture

We can picture our future program as having two main parts.

The first part is about generating candidate passwords. This could be done by either loading passwords from a dictionary or by simply generating all possible words ourselves.

The second part is then responsible for testing those candidates against the archive, one by one until the password is found or no more candidates are available.

Testing millions of passwords using a brute force strategy sounds like something that is CPU bound. Therefore we should structure our program so that the second part can scale nicely with the number of cores on the host machine.

A common approach for this type of problem is to use a set of workers to process tasks from a shared queue.

![Architecture](/2022-10-03/architecture.png)

In practice, we will orchestrate the password generator and workers as threads communicating via a channel.

Channels are a type of unidirectional asynchronous communication between threads that allows information to flow between the `Sender` and the `Receiver`.

There are several flavors of channels. In our case, we need to support a single producer and multiple consumers, a.k.a. SPMC (but MPMC will do as well).

## Dictionary

In order to keep the scope small for the beginning, we will start by retrieving passwords from an existing dictionary file.

The following file [Passwords/xato-net-10-million-passwords.txt](https://github.com/danielmiessler/SecLists/blob/master/Passwords/xato-net-10-million-passwords.txt) found on Github looks like a perfect candidate.

Let's fetch it and have a peek at its content:

```bash
wget https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/xato-net-10-million-passwords.txt
```

```bash
ls -lah xato-net-10-million-passwords.txt | awk -F " " {'print $5'} 
47M
```

```bash
wc -l xato-net-10-million-passwords.txt 
5189454 xato-net-10-million-passwords.txt
```

```bash
head -10 xato-net-10-million-passwords.txt 
123456
password
12345678
qwerty
123456789
12345
1234
111111
1234567
dragon
```

It actually contains only 5.189.454 passwords but that should be more than enough for our testing use case. We can start getting our hands dirty.

```bash
cargo new zip-password-finder
```

Our program will have a thread reading the content of the password dictionary and pushing each line into a shared channel with the workers.

There will be millions of password candidates. We need something very fast.

We will use the [crossbeam-channel](https://github.com/crossbeam-rs/crossbeam) crate for our channels because they are far superior to the channels avalaible in `std:: sync:: mpsc` in every way.

Those better channels might even make it to the standard library in the [future](https://github.com/rust-lang/rust/pull/93563).

```bash
cd zip-password-finder/
cargo add crossbeam-channel
```

Here is our reader:

```rust
use crossbeam_channel::Sender;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::thread;
use std::thread::JoinHandle;

pub fn start_password_reader(file_path: PathBuf, send_password: Sender<String>) -> JoinHandle<()> {
    thread::Builder::new()
        .name("password-reader".to_string())
        .spawn(move || {
            let file = File::open(file_path).unwrap();
            let reader = BufReader::new(file);
            for line in reader.lines() {
                match send_password.send(line.unwrap()) {
                    Ok(_) => {}
                    Err(_) => break, // channel disconnected, stop thread
                }
            }
        })
        .unwrap()
}
```

There are a few interesting things to note here:

- It is a good practice to give names to threads for better error reporting and performance observability.
- The function returns a `JoinHandle` for the caller, our main thread, to wait on.
- The entire file is read and pushed into the channel. This might be a problem for larger files.

## Password checker worker

We will be using the [zip-rs](https://github.com/zip-rs/zip) for testing the password candidates pulled from the channel.

```bash
cargo add zip
```

It supports both [ZipCrypto](https://github.com/zip-rs/zip/pull/115) and [AES](https://github.com/zip-rs/zip/pull/203) encrypted zip archives.

This is the first version of the worker thread:

```rust
use crossbeam_channel::Sender;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::thread;
use std::thread::JoinHandle;

pub fn password_checker(
    index: usize,
    file_path: &Path,
    receive_password: Receiver<String>,
) -> JoinHandle<()> {
    let file = fs::File::open(file_path).expect("File should exist");
    thread::Builder::new()
        .name(format!("worker-{}", index))
        .spawn(move || {
            let mut archive = zip::ZipArchive::new(file).expect("Archive validated before-hand");
            loop {
                match receive_password.recv() {
                    Err(_) => break, // channel disconnected, stop thread
                    Ok(password) => {
                        let res = archive.by_index_decrypt(0, password.as_bytes()); // decrypt first file in archive
                        match res {
                            Err(e) => panic!("Unexpected error {:?}", e),
                            Ok(Err(_)) => (), // invalid password - continue
                            Ok(Ok(_)) => {
                                println!("Password found:{}", password);
                                break; // stop thread
                            }
                        }
                    }
                }
            }
        })
        .unwrap()
}
```

This straightforward approach is unfortunately not enough as it yields false positive passwords from time to time.

The Rustdoc for `by_index_decrypt` actually warns about it.

> This function sometimes accepts wrong passwords.
> This is because the ZIP spec only allows us to check for a 1/256 chance that the password is correct.
> There are many passwords out there that will also pass the validity checks we are able to perform.
> This is a weakness of the ZipCrypto algorithm, due to its fairly primitive approach to cryptography.

We can workaround those collisions by performing a full read of the archive with the password to make sure it is actually correct.

```diff
 use crossbeam_channel::{Receiver, Sender};
 use std::fs::File;
-use std::io::{BufRead, BufReader};
+use std::io::{BufRead, BufReader, Read};
 use std::path::{Path, PathBuf};
 use std::thread::JoinHandle;
 use std::{fs, thread};
@@ -38,10 +38,14 @@ pub fn password_checker(
        let res = archive.by_index_decrypt(0, password.as_bytes()); // decrypt first file in archive
        match res {
            Err(e) => panic!("Unexpected error {:?}", e),
            Ok(Err(_)) => (), // invalid password - continue
-           Ok(Ok(_)) => {
-               println!("Password found:{}", password);
-               break; // stop thread
+           Ok(Err(_)) => (), // invalid password
+           Ok(Ok(mut zip)) => {
+               // Validate password by reading the zip file to make sure it is not merely a hash collision.
+               let mut buffer = Vec::with_capacity(zip.size() as usize);
+               match zip.read_to_end(&mut buffer) {
+                   Err(_) => (), // password collision - continue
+                   Ok(_) => println!("Password found:{}", password),
+               }
            }
        }
    }
```

Again, a few interesting things to note here:

- Each worker thread gets a unique name.
- The worker is `looping` until the password is found or the channel is closed.
- Each worker opens the Zip file in memory to avoid extra coordination.
- The password found is printed to the console.

## Putting it together

We can now wire things up together nicely and get one step closer to our goal.

```rust
pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize) {
    let zip_file_path = Path::new(zip_path);
    let password_list_file_path = Path::new(password_list_path).to_path_buf();

    // channel with backpressure
    let (send_password, receive_password): (Sender<String>, Receiver<String>) =
        crossbeam_channel::bounded(workers * 10_000);

    // thread handle for password reader
    let password_gen_handle = start_password_reader(password_list_file_path, send_password);

    // save all workers handles
    let mut worker_handles = Vec::with_capacity(workers);
    for i in 1..=workers {
        let join_handle = password_checker(i, zip_file_path, receive_password.clone());
        worker_handles.push(join_handle);
    }

    // wait for workers to finish
    for h in worker_handles {
        h.join().unwrap();
    }

    // wait for the end of the file
    password_gen_handle.join().unwrap();
}
```

The first important point here is the use of a bounded channel between the password generator and the workers.

A bounded channel will block the sender once its capacity is reached. This is handy to implement back-pressure.

In our case, the producer is much faster than the consumers, so we are at risk of loading the entire dictionary inside the channel, which is not great for memory usage.

To avoid slowing down the consumers, the capacity is sized according to the number of workers.

Secondly, we are saving all `JoinHandle` to await the termination of all threads.

And finally, the main function!

```rust
fn main() {
    let zip_path = env::args().nth(1).unwrap();
    let dictionary_path = "/opt/xato-net-10-million-passwords.txt";
    let workers = 3;
    password_finder(&zip_path, dictionary_path, workers);
}
```

As a command line argument our program accepts the path to an encrypted Zip file, which will be brute forced using a dictionary with 3 workers.

The dictionary path is hard-coded for the time being.

For testing purposes, we need an archive encrypted using a password from the dictionary.

I am picking the entry number 1.000.000, `vaanes`, to create our encrypted test zip.

```bash
sed -ne 1000000p xato-net-10-million-passwords.txt
vaanes
```

Let's run our program!

```bash
cd /target/release
time ./zip-password-finder encrypted-test-dict.zip
```

Checking on the CPU usage with `htop` yields an expected result.

![CPU usage with 3 workers](/2022-10-03/htop-3-workers.png)

Three worker threads are going at full speed, and one thread is reading the passwords at a leisurely pace.

After 4 minutes, the program prints on the terminal.

```txt
Password found:vaanes
```

But the program does not terminate right away; it takes more than 20 minutes to finish!

```bash
real    23m36,203s
user    72m29,567s
sys     0m41,570s
```

First the good news: the program found the password!

It processed 1 million passwords in around five minutes using 3 workers which gives us:

```txt
1.000.000 passwords tested / (4 * 60 seconds) / 3 workers =
1389 passwords tested per second per worker assuming linear scaling
```

This result provides us with an idea of what can be achieved with this approach.

Secondly, the bad news: our program does not terminate properly, which is a big issue.

## Graceful shutdown

Looking at the code more closely, we can see that we terminate our threads only under specific conditions.

For the password dictionary thread:

- If the channel has no consumers attached.
- If we reach the end of the dictionary.

And for the worker threads:

- If the channel is empty and has no producer attached.
- If we find the password.

This explains why our program kept on running previously; we only stopped the thread that found the password!

The program went through the rest of the dictionary using only two workers.

There are different ways to solve this problem. We will try to come up with an **explicit** shutdown sequence that does not rely on timeout nor on the channel being disconnected.

We need a way for the worker thread that finds the password to be able to inform other threads that they can shut down.

First, let's have worker threads communicate the password to the main thread instead of simply printing it out in the terminal.

This design is much better and will enable unit testing later on!

As a follow up, once the main thread receives the password, it will notify all threads to stop using a thread-safe signal.

```diff
 use std::path::{Path, PathBuf};
+use std::sync::atomic::{AtomicBool, Ordering};
+use std::sync::Arc;
 use std::thread::JoinHandle;
 use std::{env, fs, thread};
 
-pub fn start_password_reader(file_path: PathBuf, send_password: Sender<String>) -> JoinHandle<()> {
+pub fn start_password_reader(
+    file_path: PathBuf,
+    send_password: Sender<String>,
+    stop_signal: Arc<AtomicBool>,
+) -> JoinHandle<()> {
     thread::Builder::new()
         .name("password-reader".to_string())
         .spawn(move || {
             let file = File::open(file_path).unwrap();
             let reader = BufReader::new(file);
             for line in reader.lines() {
-                match send_password.send(line.unwrap()) {
-                    Ok(_) => {}
-                    Err(_) => break, // channel disconnected, stop thread
+                if stop_signal.load(Ordering::Relaxed) {
+                    break;
+                } else {
+                    match send_password.send(line.unwrap()) {
+                        Ok(_) => {}
+                        Err(_) => break, // channel disconnected, stop thread
+                    }
                 }
             }
         })
@@ -25,13 +35,15 @@ pub fn password_checker(
     index: usize,
     file_path: &Path,
     receive_password: Receiver<String>,
+    stop_signal: Arc<AtomicBool>,
+    send_password_found: Sender<String>,
 ) -> JoinHandle<()> {
     let file = fs::File::open(file_path).expect("File should exist");
     thread::Builder::new()
         .name(format!("worker-{}", index))
         .spawn(move || {
             let mut archive = zip::ZipArchive::new(file).expect("Archive validated before-hand");
-            loop {
+            while !stop_signal.load(Ordering::Relaxed) {
                 match receive_password.recv() {
                     Err(_) => break, // channel disconnected, stop thread
                     Ok(password) => {
@@ -44,7 +56,12 @@ pub fn password_checker(
                                 let mut buffer = Vec::with_capacity(zip.size() as usize);
                                 match zip.read_to_end(&mut buffer) {
                                     Err(_) => (), // password collision - continue
-                                    Ok(_) => println!("Password found:{}", password),
+                                    Ok(_) => {
+                                        // Send password and continue processing while waiting for signal
+                                        send_password_found
+                                            .send(password)
+                                            .expect("Send found password should not fail");
+                                    }
                                 }
                             }
                         }
@@ -55,7 +72,7 @@ pub fn password_checker(
         .unwrap()
 }
```

The threads can exit their looping state by probing a stop signal materialized by an `Arc<AtomicBool>` which is safe and cheap to operate.

And for the wiring and actual graceful shutdown.

```diff
-pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize) {
+pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize) -> Option<String> {
     let zip_file_path = Path::new(zip_path);
     let password_list_file_path = Path::new(password_list_path).to_path_buf();
 
@@ -63,28 +80,59 @@ pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize)
     let (send_password, receive_password): (Sender<String>, Receiver<String>) =
         crossbeam_channel::bounded(workers * 10_000);
 
+    let (send_found_password, receive_found_password): (Sender<String>, Receiver<String>) =
+        crossbeam_channel::bounded(1);
+
+    // stop signals to shutdown threads
+    let stop_workers_signal = Arc::new(AtomicBool::new(false));
+    let stop_gen_signal = Arc::new(AtomicBool::new(false));
+
     // thread handle for password reader
-    let password_gen_handle = start_password_reader(password_list_file_path, send_password);
+    let password_gen_handle = start_password_reader(
+        password_list_file_path,
+        send_password,
+        stop_gen_signal.clone(),
+    );
 
     // save all workers handles
     let mut worker_handles = Vec::with_capacity(workers);
     for i in 1..=workers {
-        let join_handle = password_checker(i, zip_file_path, receive_password.clone());
+        let join_handle = password_checker(
+            i,
+            zip_file_path,
+            receive_password.clone(),
+            stop_workers_signal.clone(),
+            send_found_password.clone(),
+        );
         worker_handles.push(join_handle);
     }
 
-    // wait for workers to finish
-    for h in worker_handles {
-        h.join().unwrap();
-    }
+    // drop reference in `main` so that it disappears completely with workers for a clean shutdown
+    drop(send_found_password);
 
-    // wait for the end of the file
-    password_gen_handle.join().unwrap();
+    match receive_found_password.recv() {
+        Ok(password_found) => {
+            // stop generating values first to avoid deadlock on channel
+            stop_gen_signal.store(true, Ordering::Relaxed);
+            password_gen_handle.join().unwrap();
+            // stop workers
+            stop_workers_signal.store(true, Ordering::Relaxed);
+            for h in worker_handles {
+                h.join().unwrap();
+            }
+            Some(password_found)
+        }
+        Err(_) => None,
+    }
 }
 
 fn main() {
     let zip_path = env::args().nth(1).unwrap();
     let dictionary_path = "/home/agourlay/Workspace/blog-data/find-password-zip/xato-net-10-million-passwords.txt";
     let workers = 3;
-    password_finder(&zip_path, dictionary_path, workers);
+
+    match password_finder(&zip_path, dictionary_path, workers) {
+        Some(password_found) => println!("Password found:{}", password_found),
+        None => println!("No password found :("),
+    }
 }

```

The shutdown procedure must be carefully handled to avoid a deadlock of our threads.

Using channels can make our threads block forever if the channel is not disconnected:

- A consuming thread blocks on an empty channel.
- A producing thread blocks on a full bounded channel.

This makes the task more difficult given that signals are efficient only if the threads are able to run their inner loop.

Given that we are using a bounded channel, it makes sense to shutdown the producer first.

In addition, it is important to manually drop `send_found_password` to shutdown properly when no password is found:

1. The password generator thread exits at the end of the dictionary.
2. All workers exit when the channel is disconnected.
3. All workers drop their clone of `Arc<send_found_password>`.
4. Deadlock occurs: `receive_found_password.recv()` won't be triggered unless all producers are gone **but** the main thread still holds the initial `Arc<send_found_password>`.

This gives us as valid shutdown sequence:

1. Drop the initial `Arc<send_found_password>`.
2. Wait for the found password from a worker.
3. Toggle shutdown signal password generator.
4. Join the password generator handle.
5. Toggle shutdown signal for workers.
6. Join all the worker handles.

Finding a correct sequence can be a bit subtle, so it is better to test it.

An alternative solution would be to use the timeout-flavored API `recv_timeout` and `send_timeout` which enable you to block only for a specific duration.

I have decided to not use those as they are not strictly required and it forces us to better understand our shutdown sequence :)

Let's give it a try!

```bash
cd /target/release
time ./zip-password-finder encrypted-test-dict.zip
Password found:vaanes

real  4m23,968s
user  13m30,767s
sys   0m7,130s
```

This is much better; the application shuts down as soon as the password is found!

But something important is still missing. As a user, we have no feedback while the program is waiting.

It would be great to see how much progress the program is making and have an idea of the estimated run time.

## Progress bar

The easiest way to visualize the progress of our program is to set up a progress bar.

One of the best crates for this is [Indicatif](https://github.com/console-rs/indicatif).

```bash
cargo add indicatif
```

The progress bar needs to be configured according to our use case.

```diff

     let zip_file_path = Path::new(zip_path);
     let password_list_file_path = Path::new(password_list_path).to_path_buf();
 
+    // Setup progress bar
+    let progress_bar = ProgressBar::new(0);
+    let progress_style = ProgressStyle::default_bar()
+        .template("[{elapsed_precise}] {wide_bar} {pos}/{len} throughput:{per_sec} (eta:{eta})")
+        .expect("Failed to create progress style");
+    progress_bar.set_style(progress_style);
+
+    // Refresh terminal 2 times per seconds to avoid flickering effect
+    let draw_target = ProgressDrawTarget::stdout_with_hz(2);
+    progress_bar.set_draw_target(draw_target);
+
+    // Size progress bar according to dictionary size
+    let file =
+        BufReader::new(File::open(password_list_file_path.clone()).expect("Unable to open file"));
+    let total_password_count = file.lines().count();
+    progress_bar.set_length(total_password_count as u64);
+
     // MPMC channel with backpressure
     let (send_password, receive_password): (Sender<String>, Receiver<String>) =
         crossbeam_channel::bounded(workers * 10_000);
@@ -103,6 +122,7 @@ pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize)
             receive_password.clone(),
             stop_workers_signal.clone(),
             send_found_password.clone(),
+            progress_bar.clone(),
         );
         worker_handles.push(join_handle);
     }
@@ -120,6 +140,7 @@ pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize)
             for h in worker_handles {
                 h.join().unwrap();
             }
+            progress_bar.finish_and_clear();
             Some(password_found)
         }
         Err(_) => None,
```

The most important points are:

- We set up a template to display some useful information regarding processing speed and ETA.
- The progress bar refresh rate is fixed to avoid flickering due to the high frequence of updates.
- The progress bar length is sized according to the length of the dictionary.

The integration is rather straightforward on the workers' side; simply increment the progress bar after each candidate.

```diff
@@ -37,6 +38,7 @@ pub fn password_checker(
     receive_password: Receiver<String>,
     stop_signal: Arc<AtomicBool>,
     send_password_found: Sender<String>,
+    progress_bar: ProgressBar,
 ) -> JoinHandle<()> {
     let file = fs::File::open(file_path).expect("File should exist");
     thread::Builder::new()
@@ -65,6 +67,7 @@ pub fn password_checker(
                                 }
                             }
                         }
+                        progress_bar.inc(1);
                     }
                 }
             }

```

Running this new version displays our new fancy progress bar in action!

![Progress bar](/2022-10-03/progressbar.png)

The processing speed and ETA confirm our previous observations.

But can we go any faster?

## Scaling up

We previously found that the program can test around 1389 passwords per second per worker when used with 3 workers.

What about automatically sizing the number of workers according to the host?

```diff
 use std::sync::atomic::{AtomicBool, Ordering};
 use std::sync::Arc;
-use std::thread::JoinHandle;
+use std::thread::{available_parallelism, JoinHandle};
 use std::{env, fs, thread};
+use std::cmp::max;
 
 pub fn start_password_reader(
     file_path: PathBuf,
@@ -151,7 +152,8 @@ fn main() {
     let zip_path = env::args().nth(1).unwrap();
     let dictionary_path = "/opt/xato-net-10-million-passwords.txt";
-    let workers = 3;
+    let num_cores = available_parallelism().unwrap().get();
+    let workers = max(1,  num_cores - 1);
```

With this change, we are using `num_core - 1` worker threads and one dictionary reader thread.

On my 8 cores machine, it yields the following usage.

![CPU usage 7 workers](/2022-10-03/htop-7-workers.png)

This is a nice CPU utilization to keep you warm during the winter.

Unfortunately, it does not seem to be much faster.

```bash
cd /target/release
time ./zip-password-finder encrypted-test-dict.zip
Password found:vaanes

real  3m57,826s
user  27m52,591s
sys   0m9,621s
```

That is barely 30 seconds faster than the 3 workers version!

It seems our program is suffering from scalability issues.

To investigate this, let's start by making the number of workers configurable through the CLI.

```diff
 fn main() {
-    let zip_path = env::args().nth(1).unwrap();
+    let mut args_iter = env::args().skip(1);
+    let zip_path = args_iter.next().unwrap();
     let dictionary_path = "/opt/xato-net-10-million-passwords.txt";
-    let num_cores = available_parallelism().unwrap().get();
-    let workers = max(1,  num_cores - 1);
+    let workers: usize = match args_iter.next() {
+        None => {
+            let num_cores = available_parallelism().unwrap().get();
+            max(1, num_cores - 1)
+        }
+        Some(count) => count.parse().unwrap(),
+    };
```

Then let's reach for our favorite CLI benchmarking tool, the fantastic [hyperfine](https://github.com/sharkdp/hyperfine).

Using the following magic incantation, we will get reliable measurements for runs with different worker count.

```bash
hyperfine --runs 2 \
 --warmup 1 \
 --export-markdown workers.md \
 --export-json workers.json \
 -n 1 "./zip-password-finder encrypted-test-dict.zip 1" \
 -n 2 "./zip-password-finder encrypted-test-dict.zip 2" \
 -n 3 "./zip-password-finder encrypted-test-dict.zip 3" \
 -n 4 "./zip-password-finder encrypted-test-dict.zip 4" \
 -n 5 "./zip-password-finder encrypted-test-dict.zip 5" \
 -n 6 "./zip-password-finder encrypted-test-dict.zip 6" \
 -n 7 "./zip-password-finder encrypted-test-dict.zip 7" \
 -n 8 "./zip-password-finder encrypted-test-dict.zip 8" 
```

After the runs, the `workers.md` file contains the following table:

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `1` | 559.522 ± 7.091 | 554.509 | 564.536 | 2.51 ± 0.03 |
| `2` | 338.590 ± 0.102 | 338.518 | 338.662 | 1.52 ± 0.00 |
| `3` | 264.297 ± 0.650 | 263.838 | 264.757 | 1.18 ± 0.00 |
| `4` | 223.284 ± 0.047 | 223.251 | 223.317 | 1.00 |
| `5` | 224.617 ± 0.082 | 224.559 | 224.675 | 1.01 ± 0.00 |
| `6` | 226.690 ± 0.421 | 226.392 | 226.987 | 1.02 ± 0.00 |
| `7` | 232.129 ± 0.009 | 232.122 | 232.135 | 1.04 ± 0.00 |
| `8` | 234.367 ± 0.118 | 234.284 | 234.450 | 1.05 ± 0.00 |

It looks quite bad. Let's plot it so that visual people can be disappointed as well.

![Whiskers plot](/2022-10-03/whiskers.png)

One would expect performance to grow linearly, but that is absolutely not the case here.

Not only is the speedup not linear, but the program only gets faster up to 4 workers at approximately 4500 passwords/sec.

Sounds like a good time to mention [Amdahl's law](https://en.wikipedia.org/wiki/Amdahl%27s_law), which predicts the theoretical speedup when using multiple processors depending on the portion of the work being parallel.

![AmdahlsLaw graph](/2022-10-03/AmdahlsLaw-wiki.png)

Our workload is **supposed** to be very parallelisable, each worker processing candidate passwords in isolation at full speed. We should be getting more impressive speedups.

The simplest explanation is that our program is not as parallel as we thought. There must be some form of hidden coordination preventing our program from scaling properly.

## Hyper-threading

However, I find it very suspicious that the best performance occurs at 4 workers. This is a nice power of 2.

I am running the benchmarks on a laptop running Linux on an Intel [i7-10610U](https://www.intel.com/content/www/us/en/products/sku/201896/intel-core-i710610u-processor-8m-cache-up-to-4-90-ghz/specifications.html) CPU.

Looking at the specification, we can see the following.

```bash
lscpu
...
Vendor ID:               GenuineIntel
  Model name:            Intel(R) Core(TM) i7-10610U CPU @ 1.80GHz
    CPU family:          6
    Model:               142
    Thread(s) per core:  2
    Core(s) per socket:  4
```

Instead of 8 cores, there are 4 physical cores and 2 logical threads per core!

In my case this is [Intel's Hyper-threading Technology](https://en.wikipedia.org/wiki/Hyper-threading), which enables cores to have two lanes of execution. The core can switch between those while waiting for data to be fetched from main memory or caches.

Outside of the various marketing performance claims from Intel, it seems that `Hyper-threading` is not adapted to all types of workload.

Given our very CPU-heavy workload, in which we need the full attention of each core on a single worker. It makes sense to not rely on it and only use the number of physical cores to size the number of workers.

```bash
cargo add num_cpus
```

The previous benchmark has also shown that the best performance occurs where the number of workers is equal to the number cores, meaning that the reader thread is very cheap in comparison.

```diff
     let workers: usize = match args_iter.next() {
-        None => {
-            let num_cores = available_parallelism().unwrap().get();
-            max(1, num_cores - 1)
-        }
+        None => num_cpus::get_physical(),
         Some(count) => count.parse().unwrap(),
     };

```

Hopefully, those workers will be allocated to different cores even if the host supports `Hyper-threading` for maximum efficiency.

## Going faster

Even limiting ourselves to physical cores, the scaling from one to four cores was not entirely linear.

For a quick sanity check, we can generate a flamegraph to see where the CPU time is spent.

![Flamegraph](/2022-10-03/flamegraph.png)

The various threads are nicely visible (full [flamegraph](/2022-10-03/flamegraph.svg) available).

It seems the reader thread spends most of its time snoozing, blocked when the channel is full, meaning that it is not a bottleneck.

We can zoom in on one of the workers.

![Flamegraph](/2022-10-03/flamegraph-worker.png)

It is basically spending most of its time in `sha1::compress::soft::compress` in a deep call stack from `zip-rs`.

There is nothing obvious to optimize from our worker code  given the decryption API we have to work with.

We can focus on decreasing potential synchronization issues between our worker threads. When can they possibly interfere with each other?

Looking at the code closely, we can see that for every password candidate the workers are accessing:

- the receive channel handle
- the shutdown signal
- the progress bar

A first hypothesis is that those actions increase the cost of processing a single candidate and introduce some form of coordination between threads as they are accessing shared memory.

A naive approach to reducing coordination is to give more to the workers to process in isolation by, for instance, batching up a bunch of candidates together in the channel.

What would the optimal batch size be? Let's implement batching and make the batch size configurable in place of the "workers" argument for a quick experiment.

First batching the reader thread:

```diff
 pub fn start_password_reader(
     file_path: PathBuf,
-    send_password: Sender<String>,
+    send_password: Sender<Vec<String>>,
+    batch_size: usize,
     stop_signal: Arc<AtomicBool>,
 ) -> JoinHandle<()> {
     thread::Builder::new()
@@ -19,13 +20,18 @@ pub fn start_password_reader(
         .spawn(move || {
             let file = File::open(file_path).unwrap();
             let reader = BufReader::new(file);
+            let mut batch = Vec::with_capacity(batch_size);
             for line in reader.lines() {
-                if stop_signal.load(Ordering::Relaxed) {
-                    break;
-                } else {
-                    match send_password.send(line.unwrap()) {
-                        Ok(_) => {}
-                        Err(_) => break, // channel disconnected, stop thread
+                batch.push(line.unwrap());
+                // push once the batch is full
+                if batch.len() == batch_size {
+                    if stop_signal.load(Ordering::Relaxed) {
+                        break;
+                    } else {
+                        match send_password.send(batch.clone()) {
+                            Ok(_) => batch.clear(),
+                            Err(_) => break, // channel disconnected, stop thread
+                        }
                     }
```

Then the worker thread:

```diff
 pub fn password_checker(
     index: usize,
     file_path: &Path,
-    receive_password: Receiver<String>,
+    receive_password: Receiver<Vec<String>>,
     stop_signal: Arc<AtomicBool>,
     send_password_found: Sender<String>,
     progress_bar: ProgressBar,
@@ -49,26 +55,30 @@ pub fn password_checker(
             while !stop_signal.load(Ordering::Relaxed) {
                 match receive_password.recv() {
                     Err(_) => break, // channel disconnected, stop thread
-                    Ok(password) => {
-                        let res = archive.by_index_decrypt(0, password.as_bytes());
-                        match res {
-                            Err(e) => panic!("Unexpected error {:?}", e),
-                            Ok(Err(_)) => (), // invalid password - continue
-                            Ok(Ok(mut zip)) => {
-                                // Validate password by reading the zip file to make sure it is not merely a hash collision.
-                                let mut buffer = Vec::with_capacity(zip.size() as usize);
-                                match zip.read_to_end(&mut buffer) {
-                                    Err(_) => (), // password collision - continue
-                                    Ok(_) => {
-                                        // Send password and continue processing while waiting for signal
-                                        send_password_found
-                                            .send(password)
-                                            .expect("Send found password should not fail");
+                    Ok(passwords) => {
+                        let passwords_len = passwords.len() as u64;
+                        // process batch
+                        for password in passwords {
+                            let res = archive.by_index_decrypt(0, password.as_bytes());
+                            match res {
+                                Err(e) => panic!("Unexpected error {:?}", e),
+                                Ok(Err(_)) => (), // invalid password - continue
+                                Ok(Ok(mut zip)) => {
+                                    // Validate password by reading the zip file to make sure it is not merely a hash collision.
+                                    let mut buffer = Vec::with_capacity(zip.size() as usize);
+                                    match zip.read_to_end(&mut buffer) {
+                                        Err(_) => (), // password collision - continue
+                                        Ok(_) => {
+                                            // Send password and continue processing while waiting for signal
+                                            send_password_found
+                                                .send(password)
+                                                .expect("Send found password should not fail");
+                                        }
                                     }
                                 }
                             }
                         }
-                        progress_bar.inc(1);
+                        progress_bar.inc(passwords_len);
                     }
                 }
             }
```

And a bit of wiring up:

```diff
-pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize) -> Option<String> {
+pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize, batch_size: usize) -> Option<String> {
     let zip_file_path = Path::new(zip_path);
     let password_list_file_path = Path::new(password_list_path).to_path_buf();
 
@@ -97,7 +107,7 @@ pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize)
     progress_bar.set_length(total_password_count as u64);
 
     // MPMC channel with backpressure
-    let (send_password, receive_password): (Sender<String>, Receiver<String>) =
+    let (send_password, receive_password): (Sender<Vec<String>>, Receiver<Vec<String>>) =
         crossbeam_channel::bounded(workers * 10_000);
 
     let (send_found_password, receive_found_password): (Sender<String>, Receiver<String>) =
@@ -111,6 +121,7 @@ pub fn password_finder(zip_path: &str, password_list_path: &str, workers: usize)
     let password_gen_handle = start_password_reader(
         password_list_file_path,
         send_password,
+        batch_size,
         stop_gen_signal.clone(),
     );
 
@@ -153,12 +164,11 @@ fn main() {
     let zip_path = args_iter.next().unwrap();
     let dictionary_path =
         "/home/agourlay/Workspace/blog-data/find-password-zip/xato-net-10-million-passwords.txt";
-    let workers: usize = match args_iter.next() {
-        None => num_cpus::get_physical(),
-        Some(count) => count.parse().unwrap(),
-    };
+    let batch_size: usize = args_iter.next().unwrap().parse().unwrap();
+
+    let workers: usize = num_cpus::get_physical();
 
-    match password_finder(&zip_path, dictionary_path, workers) {
+    match password_finder(&zip_path, dictionary_path, workers, batch_size) {
         Some(password_found) => println!("Password found:{}", password_found),
         None => println!("No password found :("),
     }
```

Using Hyperfine again, we will compare different batch sizes.

```bash
hyperfine --runs 2 \
 --warmup 1 \
 --export-markdown batch.md \
 --export-json batch.json \
 -n 10 "./zip-password-finder encrypted-test-dict.zip 10" \
 -n 50 "./zip-password-finder encrypted-test-dict.zip 10" \
 -n 100 "./zip-password-finder encrypted-test-dict.zip 100" \
 -n 500 "./zip-password-finder encrypted-test-dict.zip 500" \
 -n 1000 "./zip-password-finder encrypted-test-dict.zip 1000" \
 -n 5000 "./zip-password-finder encrypted-test-dict.zip 5000" \
 -n 10000 "./zip-password-finder encrypted-test-dict.zip 10000" 
```

It seems `1000` yields the best results.

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `10` | 234.756 ± 0.292 | 234.550 | 234.963 | 1.09 ± 0.00 |
| `50` | 226.616 ± 9.372 | 219.989 | 233.243 | 1.05 ± 0.04 |
| `100` | 216.498 ± 1.364 | 215.534 | 217.462 | 1.00 ± 0.01 |
| `500` | 217.122 ± 1.992 | 215.714 | 218.531 | 1.00 ± 0.01 |
| `1000` | 216.080 ± 0.066 | 216.033 | 216.127 | 1.00 |
| `5000` | 218.929 ± 0.114 | 218.848 | 219.009 | 1.01 ± 0.00 |
| `10000` | 222.792 ± 0.213 | 222.642 | 222.943 | 1.03 ± 0.00 |

However, the version without batching for 4 cores used to run in 224 seconds. That's only an 8 second improvement. I am not sure it is worth the added complexity.

We started from a wild guess regarding the source of the synchronization, so we should not be surprised by the disappointing results.

We are stopping the performance investigation here in order to save some content for the future :)

## Password generator

Our dictionary approach was great to get us started, but in real life, it is rather improbable to find the password you are targeting within a dictionary.

Well, at least it did not work for me.

A password generator is present in the final code available at [zip-password-finder](https://github.com/agourlay/zip-password-finder) but I won't go into the implementation details because the code is rather ugly and does not add much at this point.

What we need is to generate all the possible passwords based on a set of constraints.

First, the minimum and maximum length to generate. For instance, between 3 and 7 characters.

Second, the charset to use. It could be only letters, with uppercase, maybe with digits and punctuation.

We can compute the number of passwords possible based on those constraints.

```rust
let mut total_password_count = 0;
for i in min_password_len..=max_password_len {
    total_password_count += charset_len.pow(i as u32)
}
```

Here is an example to convince yourself that this grows very fast.

Given a charset with lowercase letters, upper case laters and digits. Forming a set of `26 + 26 + 10 = 62` elements.

A simple 7 characters passwords using elements from this charset yields `62^7 = 3.521.614.606.208` combinations.

`62^7 passwords / 4500 passwords per sec / 60 / 60 / 24 / 365 =~ 25 years`

## Future work

A naive brute force strategy requires much better performance to be tractable.

Fixing the scalability issue is the most important task to make this application run efficiently on machines with a higher core count.

Then, improving the nominal performance per worker by investigating possible gains in the `zip.rs` crate or a different approach to get a multiplying effect.

## Conclusion

In this article we have built a simple tool in Rust to brute force the password of protected ZIP archives.

It can process around 4500 passwords/sec on 4 cores machines and have issues scaling up which makes it impractical for non trivial passwords.

To get there we have learned how to apply the `pool of workers` pattern and how to shut it down gracefully.

We also learned how to measure performance in a systematic way and discussed scalability expectations.

At a more general level, we confirmed that long passwords are very efficient against brute force attacks.

This fact has been very well described in this [xkcd](https://xkcd.com/936/) comic.

![XKCD 936](/2022-10-03/xkcd_password_strength.png)

And that's all for today, I hope you learned a thing or two on the way - thank you for making it to the end!

If you want to play with the application, the full code with better error handling & proper CLI is available at [zip-password-finder](https://github.com/agourlay/zip-password-finder).
