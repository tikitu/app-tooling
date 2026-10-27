extern void scrollCheckStart(void);
__attribute__((constructor)) static void load(void) { scrollCheckStart(); }
