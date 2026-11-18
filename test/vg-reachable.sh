#!/bin/sh
# vg-reachable.sh LOG: succeed if every "still reachable" loss record in
# the valgrind log LOG (from --show-leak-kinds=all) is memory the program
# was right not to free, and print every other record:
#
# - memory allocated by poc's collector, GarbageCollectedHeap: its heap
#   chunks and its finalization and marking tables, which it never frees;
# - the dynamic loader's own memory for a library loaded with dlopen
#   (a stack through glibc's dl-open.c). getaddrinfo loads the NSS
#   modules (/etc/nsswitch.conf's "hosts:") so, and glibc keeps them
#   loaded until the program exits;
# - memory allocated within tls_init, which polibtls's Tls calls once:
#   OpenSSL's global state and libtls's default config, kept for the
#   life of the process (polibtls's vg-reachable.sh, which needs
#   valgrind's --num-callers large, 60, to see tls_init in the stack);
# - OpenSSL's caches, filled on first use after tls_init and kept for
#   the life of the process: algorithm implementations fetched from its
#   providers, key decoders, and the thread's error queue (polibtls's
#   too).
#
# Any other still-reachable block is memory the program should have
# freed - a libtls config, context or connection, or something a C part
# allocated, whose address is held only in the Oberon heap. Adapted
# from polibfyaml's, and polibtls's.
#
# The allocator is the first frame after the C library's malloc, calloc or
# realloc in the record's stack.
awk '
  function finish() {
    if (inrec && first != "" && first !~ /GarbageCollectedHeap\./ && !dlopen && !tlsinit && !cache) {
      print rec; print first; bad = 1
    }
    inrec = 0
  }
  / are still reachable in loss record / {
    finish(); inrec = 1; first = ""; dlopen = 0; tlsinit = 0; cache = 0; rec = $0; next
  }
  inrec && /(at|by) 0x/ {
    if ($0 ~ /\(dl-open\.c:/) dlopen = 1
    if ($0 ~ /: tls_init \(/) tlsinit = 1
    if ($0 ~ /: (ossl_method_construct|ossl_method_store_cache_set|OSSL_DECODER_CTX_new_for_pkey|ERR_set_debug|ERR_vset_error|ERR_add_error_vdata)[ .(]/) cache = 1
    if ($0 ~ /: (malloc|calloc|realloc) \(/) next
    if (first == "") first = $0
    next
  }
  inrec && /^==[0-9]+== *$/ { finish() }
  END { finish(); exit bad }
' "$1"
