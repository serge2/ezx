-record(keyboard, {
    matrix :: ezx_keyboard:key_matrix()
}).

%% ZX Spectrum keyboard matrix: 8 half-rows, 5 keys each.
%% Each byte has bits 0-4: 0 = key pressed, 1 = not pressed.
%% Half-row selected when corresponding bit in address A8-A12 is 0.
%% Default: all keys released (0x1F = all bits set).
-define(KEYBOARD_DEFAULT, {16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F}).

-define(KEY_SPACE,      {8, 0}).
-define(KEY_SYMB_SHIFT, {8, 1}).
-define(KEY_M,          {8, 2}).
-define(KEY_N,          {8, 3}).
-define(KEY_B,          {8, 4}).

-define(KEY_ENTER,      {7, 0}).
-define(KEY_L,          {7, 1}).
-define(KEY_K,          {7, 2}).
-define(KEY_J,          {7, 3}).
-define(KEY_H,          {7, 4}).

-define(KEY_P,          {6, 0}).
-define(KEY_O,          {6, 1}).
-define(KEY_I,          {6, 2}).
-define(KEY_U,          {6, 3}).
-define(KEY_Y,          {6, 4}).

-define(KEY_0,          {5, 0}).
-define(KEY_9,          {5, 1}).
-define(KEY_8,          {5, 2}).
-define(KEY_7,          {5, 3}).
-define(KEY_6,          {5, 4}).

-define(KEY_1,          {4, 0}).
-define(KEY_2,          {4, 1}).
-define(KEY_3,          {4, 2}).
-define(KEY_4,          {4, 3}).
-define(KEY_5,          {4, 4}).

-define(KEY_Q,          {3, 0}).
-define(KEY_W,          {3, 1}).
-define(KEY_E,          {3, 2}).
-define(KEY_R,          {3, 3}).
-define(KEY_T,          {3, 4}).

-define(KEY_A,          {2, 0}).
-define(KEY_S,          {2, 1}).
-define(KEY_D,          {2, 2}).
-define(KEY_F,          {2, 3}).
-define(KEY_G,          {2, 4}).

-define(KEY_CAPS_SHIFT, {1, 0}).
-define(KEY_Z,          {1, 1}).
-define(KEY_X,          {1, 2}).
-define(KEY_C,          {1, 3}).
-define(KEY_V,          {1, 4}).


