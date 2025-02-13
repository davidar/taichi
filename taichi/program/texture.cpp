#include "taichi/program/texture.h"
#include "taichi/program/ndarray.h"
#include "taichi/program/program.h"
#include "taichi/rhi/device.h"
#include "taichi/ir/snode.h"

namespace taichi {
namespace lang {

Texture::Texture(Program *prog,
                 const DataType type,
                 int num_channels,
                 int width,
                 int height,
                 int depth)
    : dtype_(type),
      num_channels_(num_channels),
      width_(width),
      height_(height),
      depth_(depth),
      prog_(prog) {
  GraphicsDevice *device =
      static_cast<GraphicsDevice *>(prog_->get_graphics_device());

  TI_TRACE(
      "Create image, gfx device {}, type={}, channels={}, w={}, h={}, d={}",
      (void *)device, type.to_string(), num_channels, width, height, depth);

  TI_ASSERT(num_channels > 0 && num_channels <= 4);

  ImageParams img_params;
  img_params.dimension = depth > 1 ? ImageDimension::d3D : ImageDimension::d2D;
  img_params.format = get_format(type, num_channels);
  img_params.x = width;
  img_params.y = height;
  img_params.z = depth;
  img_params.initial_layout = ImageLayout::undefined;
  texture_alloc_ = device->create_image(img_params);

  format_ = img_params.format;

  TI_TRACE("image created, gfx device {}", (void *)device);
}

Texture::Texture(DeviceAllocation &devalloc,
                 const DataType type,
                 int num_channels,
                 int width,
                 int height,
                 int depth)
    : texture_alloc_(devalloc),
      dtype_(type),
      num_channels_(num_channels),
      width_(width),
      height_(height),
      depth_(depth) {
  format_ = get_format(type, num_channels);
}

BufferFormat Texture::get_format(DataType type, int num_channels) {
  BufferFormat format;
  if (type == PrimitiveType::f16) {
    if (num_channels == 1) {
      format = BufferFormat::r16f;
    } else if (num_channels == 2) {
      format = BufferFormat::rg16f;
    } else if (num_channels == 4) {
      format = BufferFormat::rgba16f;
    } else {
      TI_ERROR("Invalid texture channels");
    }
  } else if (type == PrimitiveType::u16) {
    if (num_channels == 1) {
      format = BufferFormat::r16;
    } else if (num_channels == 2) {
      format = BufferFormat::rg16;
    } else if (num_channels == 4) {
      format = BufferFormat::rgba16;
    } else {
      TI_ERROR("Invalid texture channels");
    }
  } else if (type == PrimitiveType::u8) {
    if (num_channels == 1) {
      format = BufferFormat::r8;
    } else if (num_channels == 2) {
      format = BufferFormat::rg8;
    } else if (num_channels == 4) {
      format = BufferFormat::rgba8;
    } else {
      TI_ERROR("Invalid texture channels");
    }
  } else if (type == PrimitiveType::f32) {
    if (num_channels == 1) {
      format = BufferFormat::r32f;
    } else if (num_channels == 2) {
      format = BufferFormat::rg32f;
    } else if (num_channels == 3) {
      format = BufferFormat::rgb32f;
    } else if (num_channels == 4) {
      format = BufferFormat::rgba32f;
    } else {
      TI_ERROR("Invalid texture channels");
    }
  } else {
    TI_ERROR("Invalid texture dtype");
  }
  return format;
}

intptr_t Texture::get_device_allocation_ptr_as_int() const {
  return reinterpret_cast<intptr_t>(&texture_alloc_);
}

void Texture::from_ndarray(Ndarray *ndarray) {
  auto semaphore = prog_->flush();

  GraphicsDevice *device =
      static_cast<GraphicsDevice *>(prog_->get_graphics_device());
  Stream *stream = device->get_compute_stream();
  auto cmdlist = stream->new_command_list();

  BufferImageCopyParams params;
  params.buffer_row_length = ndarray->shape[0];
  params.buffer_image_height = ndarray->shape[1];
  params.image_mip_level = 0;
  params.image_extent.x = width_;
  params.image_extent.y = height_;
  params.image_extent.z = depth_;

  cmdlist->buffer_barrier(ndarray->ndarray_alloc_);
  cmdlist->image_transition(texture_alloc_, ImageLayout::undefined,
                            ImageLayout::transfer_dst);
  cmdlist->buffer_to_image(texture_alloc_, ndarray->ndarray_alloc_.get_ptr(0),
                           ImageLayout::transfer_dst, params);

  stream->submit_synced(cmdlist.get(), {semaphore});
}

DevicePtr get_device_ptr(taichi::lang::Program *program, SNode *snode) {
  SNode *dense_parent = snode->parent;
  SNode *root = dense_parent->parent;

  int tree_id = root->get_snode_tree_id();
  DevicePtr root_ptr = program->get_snode_tree_device_ptr(tree_id);

  return root_ptr.get_ptr(program->get_field_in_tree_offset(tree_id, snode));
}

void Texture::from_snode(SNode *snode) {
  auto semaphore = prog_->flush();

  TI_ASSERT(snode->is_path_all_dense);

  GraphicsDevice *device =
      static_cast<GraphicsDevice *>(prog_->get_graphics_device());

  DevicePtr devptr = get_device_ptr(prog_, snode);

  Stream *stream = device->get_compute_stream();
  auto cmdlist = stream->new_command_list();

  BufferImageCopyParams params;
  params.buffer_row_length = snode->shape_along_axis(0);
  params.buffer_image_height = snode->shape_along_axis(1);
  params.image_mip_level = 0;
  params.image_extent.x = width_;
  params.image_extent.y = height_;
  params.image_extent.z = depth_;

  cmdlist->buffer_barrier(devptr);
  cmdlist->image_transition(texture_alloc_, ImageLayout::undefined,
                            ImageLayout::transfer_dst);
  cmdlist->buffer_to_image(texture_alloc_, devptr, ImageLayout::transfer_dst,
                           params);

  stream->submit_synced(cmdlist.get(), {semaphore});
}

Texture::~Texture() {
  if (prog_) {
    GraphicsDevice *device =
        static_cast<GraphicsDevice *>(prog_->get_graphics_device());
    device->destroy_image(texture_alloc_);
  }
}

}  // namespace lang
}  // namespace taichi
