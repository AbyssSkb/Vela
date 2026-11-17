use jni::{
    objects::{GlobalRef, JObject},
    JNIEnv,
};
use std::sync::OnceLock;

static CONTEXT: OnceLock<GlobalRef> = OnceLock::new();

#[no_mangle]
pub extern "system" fn Java_com_example_vela_VelaApplication_initializeIroh(
    mut env: JNIEnv,
    _application: JObject,
    context: JObject,
) {
    let result = (|| -> jni::errors::Result<()> {
        let vm = env.get_java_vm()?;
        let context = env.new_global_ref(context)?;
        CONTEXT.get_or_init(|| {
            // Both pointers must remain valid for the lifetime of the process.
            unsafe {
                iroh::dns::install_android_jni_context(
                    vm.get_java_vm_pointer().cast(),
                    context.as_obj().as_raw().cast(),
                );
            }
            context
        });
        Ok(())
    })();
    if let Err(error) = result {
        let _ = env.throw_new("java/lang/IllegalStateException", error.to_string());
    }
}
