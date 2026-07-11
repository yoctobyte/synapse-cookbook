# The Blocking Model & Threads

Synapse is a **blocking** socket library. That is a deliberate design choice, not
a limitation, and understanding it is the key to using Synapse well.

## The era it came from

When Synapse was designed, `async`/`await` did not exist as a language construct,
and reliable preemptive **timeslicing** of threads was still being researched and
proven. Two schools competed for network I/O:

- **Non-blocking / select loops** — one thread juggling many sockets via a state
  machine. Powerful, but the code becomes a tangle of callbacks and saved state.
- **Blocking + threads** — each connection handled by straight-line code in its
  own thread; the OS scheduler interleaves them.

Synapse bet on the second, *provided* you had dependable timeouts and threads.
That bet aged well: the code reads top-to-bottom like a description of the
protocol, and scaling to many connections is "spawn more threads."

## What "blocking with timeouts" means

Every read/write takes a timeout in milliseconds. A call returns when the
operation completes **or** the timeout elapses — it never hangs forever:

```pascal
sock.Connect(host, port);            // blocks until connected or ConnectTimeout
line := sock.RecvString(5000);       // blocks up to 5 s for a CRLF-terminated line
sock.SendString('HELLO' + CRLF);     // blocks until sent
if sock.LastError <> 0 then ...      // every call reports status, no exceptions-as-flow
```

The timeout is what makes blocking *safe*: no runaway waits, and you can build
keep-alive and cancellation on top of it. `CanRead(timeout)` / `CanWrite(timeout)`
let you poll readiness without committing to a read — the ingredients of a select
loop, if you want one, without leaving the blocking API.

## Why this makes concurrency simple

Because each socket's code is linear and self-contained, concurrency is just
threading:

```pascal
type
  TConnThread = class(TThread)
    FSock: TTCPBlockSocket;
    procedure Execute; override;   // straight-line protocol code here
  end;
```

One connection, one thread, one readable `Execute`. No shared state machine, no
re-entrancy puzzles per socket. This is exactly the model that `pastella` (and
Visual Synapse's servers) built on: a listener thread accepts, then hands each
connection to its own handler thread, each speaking the protocol in plain
sequential code.

> **The transferable lesson:** a simple I/O model plus the OS scheduler often
> beats a clever single-threaded event loop — in *readability* always, and in
> throughput more often than people expect. Synapse chose boring-and-correct, and
> it is still in service two decades later.

## Practical notes

- Give every socket a **thread of its own** for servers; never share one
  `TBlockSocket` across threads.
- Choose timeouts per protocol step; they double as your liveness policy.
- Check `LastError`/`LastErrorDesc` after operations — Synapse reports rather
  than throws, keeping the linear flow intact.
