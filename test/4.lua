utils = require "utils"

utils.StartRun("4")

utils.MemTest("@test", {{0x07, "92"}, {0x08, "52"}})

-- The test appears to be done in a few frames. Let's run this several times
-- just in case.
for i = 0, 150, 1 do
  emu.frameadvance();
end

utils.EndRun()
