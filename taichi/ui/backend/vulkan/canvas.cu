#include "canvas.h"
#include "../../utils/utils.h"
#include "../../common/constants.h"
#include "vulkan_cuda_interop.h"
#include "vulkan_cuda_interop.h"


namespace vulkan{

Canvas::Canvas(AppContext* app_context):app_context_(app_context){
    create_semaphores();
    import_semaphores();

    cached_command_buffers_.resize(app_context_->swap_chain->swap_chain_images.size());
    for(int i = 0;i<app_context_->swap_chain->swap_chain_images.size();++i){
        cached_command_buffers_[i] = VK_NULL_HANDLE;
    }
}

void Canvas::clear_command_buffer_cache(){
    for(int i = 0;i<cached_command_buffers_.size();++i){
        if(cached_command_buffers_[i]!=VK_NULL_HANDLE){
            vkFreeCommandBuffers(app_context_->device, app_context_->command_pool, 1, &cached_command_buffers_[i]);
        }
        cached_command_buffers_[i]=VK_NULL_HANDLE;
    }
}

void Canvas::create_semaphores(){
    create_semaphore(prev_draw_finished_vk_,app_context_->device);
    create_semaphore(this_draw_data_ready_vk_,app_context_->device);
}

 
template <typename T>
T* Canvas::get_renderable_of_type(){
    if(next_renderable_ >= renderables_.size()){
        renderables_.push_back(std::move(std::unique_ptr<Renderable>{std::make_unique<T>(app_context_).release()}));
        clear_command_buffer_cache();
    } 
    else if(dynamic_cast<T*>(renderables_[next_renderable_].get()) == nullptr){
        renderables_.insert(renderables_.begin()+next_renderable_,std::move(std::unique_ptr<Renderable>{std::make_unique<T>(app_context_).release()})); 
        clear_command_buffer_cache();
    }

    //printf("renderables_.size:%ld  next_renderable_:%d  \n",renderables_.size(),next_renderable_);

    if(T* t = dynamic_cast<T*>(renderables_[next_renderable_].get())){
        return t;
    }
    else{
        throw std::runtime_error("Failed to Get Renderable.");
    }
}
void Canvas::set_background_color(const glm::vec3& color){
    background_color_ = color;
}
 
void Canvas::set_image(const SetImageInfo& info) {
    // printf("calling set_image \n");
    SetImage* s  = get_renderable_of_type<SetImage>();
    s->update_data(info);
    next_renderable_ += 1;
}

void Canvas::triangles(const TrianglesInfo& info) {
    Triangles* triangles  = get_renderable_of_type<Triangles>();
    triangles->update_data(info);
    next_renderable_ += 1;
}

void Canvas::lines(const LinesInfo& info) {
    Lines* lines  = get_renderable_of_type<Lines>();
    lines->update_data(info);
    next_renderable_ += 1;
}

void Canvas::circles(const CirclesInfo& info)  {
    Circles* circles  = get_renderable_of_type<Circles>();
    circles->update_data(info);
    next_renderable_ += 1;
}

void Canvas::mesh(const MeshInfo& info, Scene* scene){
    Mesh* mesh = get_renderable_of_type<Mesh>();
    mesh -> update_data(info,*scene);
    next_renderable_ += 1;
}

void  Canvas::particles(const ParticlesInfo& info, Scene* scene){
    Particles* particles = get_renderable_of_type<Particles>();
    particles -> update_data(info, *scene);
    next_renderable_ += 1;
}

void Canvas::scene(SceneBase* scene_base){
    if(Scene* scene = dynamic_cast<Scene*>(scene_base)){
        if(scene -> point_lights_.size() == 0){
            printf("warning, there are no light sources in the scene.\n");
        }
        float aspect_ratio = app_context_ -> swap_chain -> swap_chain_extent.width / (float) app_context_ -> swap_chain -> swap_chain_extent.height;
        scene -> update_ubo(aspect_ratio);
        for(int i = 0; i < scene -> mesh_infos_.size() ;++i){
            mesh(scene->mesh_infos_[i],scene);
        }
        for(int i = 0; i < scene -> particles_infos_.size() ;++i){
            particles(scene->particles_infos_[i],scene);
        }
        scene -> mesh_infos_.clear();
        scene -> particles_infos_.clear();
        scene -> point_lights_.clear();
    }
    else{
        throw std::runtime_error("Scene is not vulkan scene");
    }
}

 

void Canvas::cleanup(){
    for(auto& renderable: renderables_){
        renderable -> cleanup();
    }
    vkDestroySemaphore(app_context_->device,prev_draw_finished_vk_,nullptr);
    vkDestroySemaphore(app_context_->device,this_draw_data_ready_vk_,nullptr);

}

void Canvas::cleanup_swap_chain(){
    clear_command_buffer_cache();
    for(auto& renderable: renderables_){
        renderable -> cleanup_swap_chain();
    }
}

void Canvas::recreate_swap_chain(){
    for(auto& renderable: renderables_){
        renderable -> recreate_swap_chain();
    }
}

void Canvas::import_semaphores(){
    if(app_context_->config.ti_arch == ARCH_CUDA){
        prev_draw_finished_cuda_ = (uint64_t)cuda_vk_import_semaphore(prev_draw_finished_vk_,app_context_->device);
        this_draw_data_ready_cuda_ = (uint64_t)cuda_vk_import_semaphore(this_draw_data_ready_vk_,app_context_->device);

        cuda_vk_semaphore_signal((CUexternalSemaphore)prev_draw_finished_cuda_);
    }
}

void Canvas::prepare_for_next_frame(){
    next_renderable_ = 0;
    if(app_context_->config.ti_arch == ARCH_CUDA){
        cuda_vk_semaphore_wait((CUexternalSemaphore)prev_draw_finished_cuda_);
    }
}

void Canvas::draw_frame(Gui* gui){

    uint32_t image_index = app_context_->swap_chain->curr_image_index;
    
    if (app_context_->swap_chain->images_in_flight[image_index] != VK_NULL_HANDLE) {
        vkWaitForFences(app_context_->device, 1, &app_context_->swap_chain->images_in_flight[image_index], VK_TRUE, UINT64_MAX);
    }
    app_context_->swap_chain->images_in_flight[image_index] = app_context_->swap_chain->in_flight_scenes[app_context_->swap_chain->current_frame];

    if(app_context_->config.ti_arch == ARCH_CUDA){
        cuda_vk_semaphore_signal((CUexternalSemaphore)this_draw_data_ready_cuda_);
    }
    
    
    VkCommandBuffer command_buffer;

    if(!gui -> is_empty){
        clear_command_buffer_cache();
    }

    if(cached_command_buffers_[image_index] != VK_NULL_HANDLE ){
        command_buffer = cached_command_buffers_[image_index];
    }
    else{
        //printf("recording new commandBuffer %d %ld\n",image_index,renderables_.size());

        command_buffer = create_new_command_buffer(app_context_->command_pool,app_context_->device);

        VkCommandBufferBeginInfo begin_info = {};
        begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        begin_info.flags = VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT;

        if (vkBeginCommandBuffer(command_buffer, &begin_info) != VK_SUCCESS) {
            throw std::runtime_error("failed to begin recording command buffer!");
        }

        VkRenderPassBeginInfo render_pass_info{};
        render_pass_info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        render_pass_info.renderPass = app_context_->render_pass;
        render_pass_info.framebuffer = app_context_->swap_chain->swap_chain_framebuffers[image_index];
        render_pass_info.renderArea.offset = {0, 0};
        render_pass_info.renderArea.extent = app_context_->swap_chain->swap_chain_extent;

        std::array<VkClearValue, 2> clear_values{};
        clear_values[0].color = {background_color_.x, background_color_.y, background_color_.z, 1.0f};
        clear_values[1].depthStencil = {1.0f, 0};

        render_pass_info.clearValueCount = static_cast<uint32_t>(clear_values.size());
        render_pass_info.pClearValues = clear_values.data();
        vkCmdBeginRenderPass(command_buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);

        for(int i = 0;i<next_renderable_;++i){
            renderables_[i]->record_this_frame_commands(command_buffer);
        }

        gui -> draw(command_buffer);

        vkCmdEndRenderPass(command_buffer);
        vkEndCommandBuffer(command_buffer);

        cached_command_buffers_[image_index] = command_buffer;
    }

    std::vector<VkSemaphore> wait_semaphores = {app_context_->swap_chain->image_available_semaphores[app_context_->swap_chain->current_frame]};
    std::vector<VkPipelineStageFlags> wait_stages = {VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    std::vector<VkSemaphore> signal_semaphores = {app_context_->swap_chain->render_finished_semaphores[app_context_->swap_chain->current_frame]};

    if(app_context_->config.ti_arch == ARCH_CUDA){
        wait_semaphores.push_back(this_draw_data_ready_vk_);
        wait_stages.push_back(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
        signal_semaphores.push_back(prev_draw_finished_vk_);
    }


    VkSubmitInfo submit_info{};
    submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

    
    submit_info.waitSemaphoreCount = wait_semaphores.size();
    submit_info.pWaitSemaphores = wait_semaphores.data();
    submit_info.pWaitDstStageMask = wait_stages.data();

    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command_buffer;

    submit_info.signalSemaphoreCount = signal_semaphores.size();
    submit_info.pSignalSemaphores = signal_semaphores.data();

    vkResetFences(app_context_->device, 1, &app_context_->swap_chain->in_flight_scenes[app_context_->swap_chain->current_frame]);

    if (vkQueueSubmit(app_context_->graphics_queue, 1, &submit_info, app_context_->swap_chain->in_flight_scenes[app_context_->swap_chain->current_frame]) != VK_SUCCESS) {
        throw std::runtime_error("failed to submit draw command buffer!");
    }
    
}

}
