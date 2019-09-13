#if !defined(DM_PLATFORM_ANDROID) && !defined(DM_PLATFORM_IOS)

extern "C" void IACExt()
{
	
}

int IAC_PlatformSetListener(lua_State*)
{
    // Platform specific (placeholder, for tests to build).
    return 0;
}
#endif
