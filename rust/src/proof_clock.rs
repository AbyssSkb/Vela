use std::time::Duration;

#[cfg(not(any(target_os = "android", target_os = "macos")))]
pub(crate) type ProofInstant = std::time::Instant;

#[cfg(any(target_os = "android", target_os = "macos"))]
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(crate) struct ProofInstant(u64);

#[cfg(any(target_os = "android", target_os = "macos"))]
impl ProofInstant {
    pub(crate) fn now() -> Self {
        now()
    }

    pub(crate) fn checked_add(self, duration: Duration) -> Option<Self> {
        if !is_valid(self) {
            return None;
        }
        let nanos = u64::try_from(duration.as_nanos()).ok()?;
        self.0
            .checked_add(nanos)
            .filter(|value| *value != u64::MAX)
            .map(Self)
    }

    pub(crate) fn duration_since(self, earlier: Self) -> Duration {
        if !is_valid(self) || !is_valid(earlier) {
            return Duration::MAX;
        }
        Duration::from_nanos(self.0.saturating_sub(earlier.0))
    }

    pub(crate) fn saturating_duration_since(self, earlier: Self) -> Duration {
        self.duration_since(earlier)
    }

    pub(crate) fn elapsed(self) -> Duration {
        now().duration_since(self)
    }
}

#[cfg(any(target_os = "android", target_os = "macos"))]
impl std::ops::Add<Duration> for ProofInstant {
    type Output = Self;
    fn add(self, duration: Duration) -> Self {
        if !is_valid(self) {
            return self;
        }
        Self(
            self.0
                .saturating_add(duration.as_nanos().min(u64::MAX as u128) as u64),
        )
    }
}

#[cfg(any(target_os = "android", target_os = "macos"))]
impl std::ops::Sub<Duration> for ProofInstant {
    type Output = Self;
    fn sub(self, duration: Duration) -> Self {
        if !is_valid(self) {
            return self;
        }
        Self(
            self.0
                .saturating_sub(duration.as_nanos().min(u64::MAX as u128) as u64),
        )
    }
}

#[cfg(any(target_os = "android", target_os = "macos"))]
pub(crate) fn now() -> ProofInstant {
    let mut value = std::mem::MaybeUninit::<libc::timespec>::uninit();
    #[cfg(target_os = "android")]
    let clock = libc::CLOCK_BOOTTIME;
    #[cfg(target_os = "macos")]
    let clock = libc::CLOCK_MONOTONIC_RAW;
    // A failed clock read must never make an old proof appear fresh.
    if unsafe { libc::clock_gettime(clock, value.as_mut_ptr()) } != 0 {
        return ProofInstant(u64::MAX);
    }
    let value = unsafe { value.assume_init() };
    if value.tv_sec < 0 || value.tv_nsec < 0 || value.tv_nsec >= 1_000_000_000 {
        return ProofInstant(u64::MAX);
    }
    let nanos = (value.tv_sec as u128)
        .saturating_mul(1_000_000_000)
        .saturating_add(value.tv_nsec as u128);
    ProofInstant(nanos.min((u64::MAX - 1) as u128) as u64)
}

#[cfg(not(any(target_os = "android", target_os = "macos")))]
pub(crate) fn now() -> ProofInstant {
    let _ = origin();
    std::time::Instant::now()
}

#[cfg(any(target_os = "android", target_os = "macos"))]
pub(crate) fn minimum() -> ProofInstant {
    ProofInstant(0)
}

#[cfg(not(any(target_os = "android", target_os = "macos")))]
pub(crate) fn minimum() -> ProofInstant {
    now()
}

#[cfg(not(any(target_os = "android", target_os = "macos")))]
fn origin() -> ProofInstant {
    static ORIGIN: std::sync::OnceLock<ProofInstant> = std::sync::OnceLock::new();
    *ORIGIN.get_or_init(std::time::Instant::now)
}

#[cfg(any(target_os = "android", target_os = "macos"))]
pub(crate) fn is_valid(instant: ProofInstant) -> bool {
    instant.0 != u64::MAX
}

#[cfg(not(any(target_os = "android", target_os = "macos")))]
pub(crate) fn is_valid(_: ProofInstant) -> bool {
    true
}

#[cfg(any(target_os = "android", target_os = "macos"))]
pub(crate) fn as_nanos(instant: ProofInstant) -> u64 {
    instant.0
}

#[cfg(not(any(target_os = "android", target_os = "macos")))]
pub(crate) fn as_nanos(instant: ProofInstant) -> u64 {
    instant
        .saturating_duration_since(origin())
        .as_nanos()
        .min(u64::MAX as u128) as u64
}

pub(crate) fn now_ns() -> u64 {
    as_nanos(now())
}

pub(crate) fn is_fresh(sent: ProofInstant, current: ProofInstant, lease: Duration) -> bool {
    let Some(deadline) = sent.checked_add(lease) else {
        return false;
    };
    is_valid(sent)
        && is_valid(current)
        && is_valid(deadline)
        && current >= sent
        && current < deadline
}

#[cfg(target_os = "macos")]
fn mac_deadline_ticks(deadline: ProofInstant) -> Option<isize> {
    static TIMEBASE: std::sync::OnceLock<Option<(u32, u32)>> = std::sync::OnceLock::new();
    let (numer, denom) = (*TIMEBASE.get_or_init(|| {
        let mut info = std::mem::MaybeUninit::<libc::mach_timebase_info>::uninit();
        #[allow(deprecated)]
        let result = unsafe { libc::mach_timebase_info(info.as_mut_ptr()) };
        if result != 0 {
            return None;
        }
        let info = unsafe { info.assume_init() };
        (info.numer != 0 && info.denom != 0).then_some((info.numer, info.denom))
    }))?;
    let scaled = u128::from(deadline.0).checked_mul(u128::from(denom))?;
    isize::try_from(scaled.div_ceil(u128::from(numer))).ok()
}

/// Reusable proof deadline timer whose supported platform clocks include suspend.
pub(crate) struct ProofTimer {
    #[cfg(any(target_os = "android", target_os = "macos"))]
    fd: Option<tokio::io::unix::AsyncFd<std::os::fd::OwnedFd>>,
}

impl ProofTimer {
    pub(crate) fn new() -> Self {
        #[cfg(target_os = "android")]
        let fd = {
            use std::os::fd::FromRawFd;
            let raw = unsafe {
                libc::timerfd_create(libc::CLOCK_BOOTTIME, libc::TFD_NONBLOCK | libc::TFD_CLOEXEC)
            };
            if raw < 0 {
                None
            } else {
                let owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(raw) };
                // OwnedFd remains open and refers to this timer for the lifetime of AsyncFd.
                unsafe {
                    tokio::io::unix::AsyncFd::register_with_interest(
                        owned,
                        tokio::io::Interest::READABLE,
                    )
                }
                .ok()
            }
        };
        #[cfg(target_os = "macos")]
        let fd = {
            use std::os::fd::{AsRawFd, FromRawFd};
            let raw = unsafe { libc::kqueue() };
            if raw < 0 {
                None
            } else {
                let owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(raw) };
                if unsafe { libc::fcntl(owned.as_raw_fd(), libc::F_SETFD, libc::FD_CLOEXEC) } < 0 {
                    None
                } else {
                    // OwnedFd keeps this kqueue open and stable while Tokio observes it.
                    unsafe {
                        tokio::io::unix::AsyncFd::register_with_interest(
                            owned,
                            tokio::io::Interest::READABLE,
                        )
                    }
                    .ok()
                }
            }
        };
        Self {
            #[cfg(any(target_os = "android", target_os = "macos"))]
            fd,
        }
    }

    /// May return early on a timer error; the caller must recheck its proof.
    pub(crate) async fn wait_until(&mut self, deadline: ProofInstant) {
        #[cfg(not(any(target_os = "android", target_os = "macos")))]
        tokio::time::sleep_until(deadline.into()).await;

        #[cfg(target_os = "android")]
        {
            use std::os::fd::AsRawFd;
            let current = now();
            if !is_valid(current) || !is_valid(deadline) {
                tokio::time::sleep(Duration::from_millis(500)).await;
                return;
            }
            if current >= deadline {
                return;
            }
            if let (Some(fd), Ok(seconds)) =
                (&self.fd, libc::time_t::try_from(deadline.0 / 1_000_000_000))
            {
                let spec = libc::itimerspec {
                    it_interval: libc::timespec {
                        tv_sec: 0,
                        tv_nsec: 0,
                    },
                    it_value: libc::timespec {
                        tv_sec: seconds,
                        tv_nsec: (deadline.0 % 1_000_000_000) as libc::c_long,
                    },
                };
                if unsafe {
                    libc::timerfd_settime(
                        fd.get_ref().as_raw_fd(),
                        libc::TFD_TIMER_ABSTIME,
                        &spec,
                        std::ptr::null_mut(),
                    )
                } == 0
                {
                    loop {
                        match fd.readable().await {
                            Ok(mut ready) => {
                                let read = ready.try_io(|inner| {
                                    let mut expirations = 0u64;
                                    let n = unsafe {
                                        libc::read(
                                            inner.get_ref().as_raw_fd(),
                                            &mut expirations as *mut u64 as *mut libc::c_void,
                                            std::mem::size_of::<u64>(),
                                        )
                                    };
                                    if n == std::mem::size_of::<u64>() as isize {
                                        Ok(())
                                    } else if n < 0 {
                                        Err(std::io::Error::last_os_error())
                                    } else {
                                        Err(std::io::Error::new(
                                            std::io::ErrorKind::UnexpectedEof,
                                            "short timerfd read",
                                        ))
                                    }
                                });
                                match read {
                                    Ok(Ok(())) => return,
                                    Err(_) => continue,
                                    Ok(Err(error))
                                        if error.kind() == std::io::ErrorKind::Interrupted =>
                                    {
                                        continue
                                    }
                                    Ok(Err(_)) => break,
                                }
                            }
                            Err(_) => break,
                        }
                    }
                }
            }
            self.fd = None;
            let current = now();
            let remaining = if is_valid(current) {
                deadline.duration_since(current)
            } else {
                Duration::from_millis(500)
            };
            tokio::time::sleep(remaining.min(Duration::from_millis(500))).await;
        }

        #[cfg(target_os = "macos")]
        {
            use std::os::fd::AsRawFd;
            let current = now();
            if !is_valid(current) || !is_valid(deadline) {
                tokio::time::sleep(Duration::from_millis(500)).await;
                return;
            }
            if current >= deadline {
                return;
            }
            if let (Some(fd), Some(ticks)) = (&self.fd, mac_deadline_ticks(deadline)) {
                let registered = {
                    let change = libc::kevent {
                        ident: 1,
                        filter: libc::EVFILT_TIMER,
                        flags: libc::EV_ADD | libc::EV_ONESHOT,
                        fflags: libc::NOTE_ABSOLUTE
                            | libc::NOTE_MACHTIME
                            | libc::NOTE_MACH_CONTINUOUS_TIME,
                        data: ticks,
                        udata: std::ptr::null_mut(),
                    };
                    (unsafe {
                        libc::kevent(
                            fd.get_ref().as_raw_fd(),
                            &change,
                            1,
                            std::ptr::null_mut(),
                            0,
                            std::ptr::null(),
                        )
                    }) == 0
                };
                if registered {
                    loop {
                        match fd.readable().await {
                            Ok(mut ready) => {
                                let read = ready.try_io(|inner| {
                                    let mut event = std::mem::MaybeUninit::<libc::kevent>::uninit();
                                    let timeout = libc::timespec {
                                        tv_sec: 0,
                                        tv_nsec: 0,
                                    };
                                    let n = unsafe {
                                        libc::kevent(
                                            inner.get_ref().as_raw_fd(),
                                            std::ptr::null(),
                                            0,
                                            event.as_mut_ptr(),
                                            1,
                                            &timeout,
                                        )
                                    };
                                    if n > 0 {
                                        Ok(())
                                    } else if n == 0 {
                                        Err(std::io::Error::from(std::io::ErrorKind::WouldBlock))
                                    } else {
                                        Err(std::io::Error::last_os_error())
                                    }
                                });
                                match read {
                                    Ok(Ok(())) => return,
                                    Err(_) => continue,
                                    Ok(Err(error))
                                        if error.kind() == std::io::ErrorKind::Interrupted =>
                                    {
                                        continue
                                    }
                                    Ok(Err(_)) => break,
                                }
                            }
                            Err(_) => break,
                        }
                    }
                }
            }
            self.fd = None;
            let current = now();
            let remaining = if is_valid(current) {
                deadline.duration_since(current)
            } else {
                Duration::from_millis(500)
            };
            tokio::time::sleep(remaining.min(Duration::from_millis(500))).await;
        }
    }
}

#[cfg(test)]
#[path = "proof_clock_tests.rs"]
mod tests;
