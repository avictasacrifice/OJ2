shader_type spatial;
// Режимы рендера: смешивание, непрозрачная глубина, отсечение задних граней
render_mode blend_mix, depth_draw_opaque, cull_back;

// Настройки, которые можно менять в инспекторе
uniform vec4 water_color : source_color = vec4(0.1, 0.9, 0.6, 0.8); // Цвет воды
uniform sampler2D wave_noise : filter_linear_mipmap, repeat_enable; // Текстура шума для волн
uniform float wave_speed : hint_range(0.0, 1.0) = 0.05; // Скорость волн
uniform float wave_height : hint_range(0.0, 2.0) = 0.3; // Высота волн

void vertex() {
    // Смещаем вершины по оси Y на основе текстуры шума и времени
    float wave = texture(wave_noise, VERTEX.xz * 0.1 + TIME * wave_speed).r;
    VERTEX.y += wave * wave_height;
}

void fragment() {
    // Задаем цвет, прозрачность и отражающие свойства
    ALBEDO = water_color.rgb;
    ALPHA = water_color.a;
    METALLIC = 0.6; // Делаем воду металлической/отражающей
    ROUGHNESS = 0.1; // Гладкая поверхность для бликов
}