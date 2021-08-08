#pragma once

#include <iostream>
#include <fstream>
#include <stdexcept>
#include <algorithm>
#include <chrono>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <array>
#include <optional>
#include <set>
#include "../../../utils/utils.h"
#include "taichi/ui/backend/vulkan/vertex.h"
#include "taichi/ui/backend/vulkan/vulkan_utils.h"
#include "taichi/ui/backend/vulkan/app_context.h"
#include "taichi/ui/backend/vulkan/swap_chain.h"
#include "taichi/ui/backend/vulkan/renderable.h"
#include "../../../common/field_info.h"
#include "../../../common/canvas_base.h"

TI_UI_NAMESPACE_BEGIN

namespace vulkan {

class Triangles final : public Renderable {
 public:
  Triangles(AppContext *app_context);

  void update_data(const TrianglesInfo &info);

 private:
  struct UniformBufferObject {
    alignas(16) glm::vec3 color;
    int use_per_vertex_color;
  };

  void init_triangles(AppContext *app_context,
                      int vertices_count,
                      int indices_count);

  void update_ubo(glm::vec3 color, bool use_per_vertex_color);

  virtual void create_descriptor_set_layout() override;

  virtual void create_descriptor_sets() override;
};

}  // namespace vulkan

TI_UI_NAMESPACE_END