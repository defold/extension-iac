#if defined(DM_PLATFORM_ANDROID) || defined(DM_PLATFORM_IOS)
#ifndef DM_IAC_EXTENSION
#define DM_IAC_EXTENSION

#include <dmsdk/sdk.h>
#include <stdint.h>

#define DM_IAC_EXTENSION_TYPE_INVOCATION 0

namespace dmIAC
{
    /**
     * Initialize IAC
     * @param params dmExtensions Initialize parameters
     * @return dmExtensions Result code
     */
    dmExtension::Result Initialize(dmExtension::Params* params);

    /**
     * Finalize IAC
     * @param params dmExtensions Finalize parameters
     * @return dmExtensions Result code
     */
    dmExtension::Result Finalize(dmExtension::Params* params);
}

#endif //DM_IAC_EXTENSION
#endif //DM_PLATFORM_ANDROID || DM_PLATFORM_IOS
