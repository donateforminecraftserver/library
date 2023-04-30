local C = ffi.C

ffi.cdef[[
    void*GetModuleHandleA(const char*);
    void*GetProcAddress(void*,const char*);
    void*CreateThread(void*,size_t,intptr_t,void*,unsigned long,unsigned long*);
    bool TerminateThread(void*,unsigned long);
    bool CloseHandle(void*);
    bool GetExitCodeThread(void*,unsigned long*);

    typedef struct
    {
        void* flink;
        void* blink;
    } list_entry_t;

    typedef struct 
    {
        unsigned short type;
        unsigned short creator_back_trace_index;
        void* critical_section;
        list_entry_t process_lock_list;
        unsigned long entry_count;
        unsigned long contention_count;
        unsigned long flags;
        unsigned short creator_back_trace_index_high;
        unsigned short spare_word;
    } critical_section_debug_t;

    typedef struct
    {
        critical_section_debug_t debug_info;
        long lock_count;
        long recursion_count;
        int owning_thread;
        void* lock_semaphore;
        unsigned long spin_count;
    } critical_section_t;

    void InitializeCriticalSection(critical_section_t*);
    void DeleteCriticalSection(critical_section_t*);
    void EnterCriticalSection(critical_section_t*);
    void LeaveCriticalSection(critical_section_t*);
]]

local create_simple_thread = ffi.cast('void*(__cdecl*)(intptr_t, intptr_t, size_t)', C.GetProcAddress(C.GetModuleHandleA('tier0.dll'), 'CreateSimpleThread'))
local release_thread_handle = ffi.cast('bool(__cdecl*)(void*)', C.GetProcAddress(C.GetModuleHandleA('tier0.dll'), 'ReleaseThreadHandle'))

local threading = {}
threading.threads = {}
threading.crits = {}

function threading:create(callback, critical, ...)
    if callback and type(callback) == 'function' then
        local args = {...}
        local sh_handle = nil
        
        local func = function()
            -- without pcall lua error handler will cause crash
            pcall(callback, args)

            -- failsafe if someone forgot to unlock critical section or if lua error occured
            if critical and type(critical) == 'userdata' then
                C.LeaveCriticalSection(critical)
            end

            -- removing this thread from csgo
            release_thread_handle(sh_handle)
        end

        local func_addr = tonumber(ffi.cast('intptr_t', ffi.cast('void*', ffi.cast('void*(*)()', func))))
        local thread = {
            handle = create_simple_thread(func_addr, 0, 0),
            is_running = function(self)
                local alloced = ffi.new('unsigned long[?]', 0)
                C.GetExitCodeThread(self.handle, alloced)
                return alloced[0] == 259
            end,
            destroy = function(self, unload)
                if critical and type(critical) == 'userdata' then
                    C.LeaveCriticalSection(critical)
                end

                C.TerminateThread(self.handle, 0)                
                -- C.CloseHandle(self.handle)
                release_thread_handle(sh_handle)
				self.handle = nil
            end,
            __gc = function(self)
                if self:is_running() then
                    self:destroy()
                end
            end
        }

        sh_handle = thread.handle

        table.insert(self.threads, thread)
        return thread
    end
end

function threading:create_critical_section()
    local critical_section = ffi.new('critical_section_t')
    local ptr = ffi.cast('critical_section_t&', critical_section)
    C.InitializeCriticalSection(ptr)

    local tbl = {
        inside = false,
        enter = function(self)
            C.EnterCriticalSection(ptr)
            self.inside = true
        end,
        leave = function(self)
            C.LeaveCriticalSection(ptr)
            self.inside = false
        end,
        access = function(self)
            return ptr
        end,
        destroy = function(self)
            if self.inside then
                self:leave()
            end

            C.DeleteCriticalSection(ptr)
            ptr = nil
        end,
        __gc = function(self)
            self:destroy()
        end
    }

    table.insert(self.crits, tbl)
    return tbl
end

function threading:terminate()
    for i=1, #self.threads do
        self.threads[i]:destroy(true)
    end

    for i=1, #self.crits do
        self.crits[i]:destroy()
    end
end

Cheat.register_callback('Unload', function()
    threading:terminate()
end)

return threading