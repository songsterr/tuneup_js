require 'open3'
require 'shellwords'
require 'FileUtils'

class ImageAssertion

  MAX_ALLOWED_DIFF_VALUE  = 1.0
  DIFF_IMAGE_FOLDER_NAME  = 'screens_diff'
  TEMP_IMAGE_FOLDER_NAME  = 'screens_temp'

  def self.assert_image(test_output, ref_images_path, image_name, threshold)

    return false unless (test_output && ref_images_path && image_name)

    diff_images_path  = File.join(test_output, DIFF_IMAGE_FOLDER_NAME)
    ref_masks_path = File.join(ref_images_path, 'masks')
    Dir.mkdir(diff_images_path) unless File.directory?(diff_images_path)

    image_file_name   = image_name + '.png'
    ref_image_path     = File.join(ref_images_path, image_file_name)
    mask_path         = File.join(ref_masks_path, image_name + '_mask.png')
    temp_images_path  = File.join(test_output, TEMP_IMAGE_FOLDER_NAME)
    diff_path         = File.join(diff_images_path, image_file_name)

    Dir.mkdir(temp_images_path) unless File.directory?(temp_images_path)

    run_folder_name   = find_last_folder(test_output)

    FileUtils.cp(File.join(run_folder_name, image_file_name), temp_images_path);
    received_instrument_path     = File.join(temp_images_path, image_file_name)

    print_status(create_status('started', "Asserting #{image_file_name}."))

    if (File.exists?(mask_path))
      received_path = File.join(temp_images_path, image_name + '_masked.png')
      mask(mask_path, received_instrument_path, received_path)
      expected_path = File.join(temp_images_path, image_name + '_ref_masked.png')
      mask(mask_path, ref_image_path, expected_path)
    else
      expected_path = ref_image_path  
      received_path = received_instrument_path
    end

    if !File.exists?(received_path) || !File.exists?(expected_path)

      error = "Expected or reference image #{image_file_name} not found."
      print_status(create_status('failed', error))
      return false

    else
      
      result = im_compare(expected_path, received_path, diff_path)
      return process_imagemagick_result(image_file_name, result, threshold)
    end
  end

private

  def self.mask(mask_path, received_path, result_path)
    `convert -page +0+0 \"#{received_path}\" -page +0+0 \"#{mask_path}\" -flatten \"#{result_path}\"`
  end

  # Iterte through folders with name Run* and return with latests run number
  def self.find_last_folder(test_output)

    folder_mask = "#{test_output}/Run";
    run_folders = Dir.glob("#{folder_mask}*")

    return nil unless run_folders.length > 0

    run_folders.sort do |x, y|
      y.gsub(folder_mask, '').to_i <=> x.gsub(folder_mask, '').to_i
    end[0]
  end

  def self.process_imagemagick_result(image_file_name, stderr, threshold)

    result_status   = 'failed'
    result_message  = "#{image_file_name} is not equal to the reference."
    assertionResult = false

    #imagemagick outputs floating point metrics value when succeeds
    compare_succeed = ( stderr.match(/[0-9]*\.?[0-9]+/).length > 0 )
    if threshold == 0
      threshold = MAX_ALLOWED_DIFF_VALUE
    end
    
    if compare_succeed
      if stderr.to_f < threshold

        result_status   = 'passed'
        result_message  = "#{image_file_name} asserted successfully."
        assertionResult = true
      else
        print_status(create_status(result_status, "expected diff is smaller than #{threshold} but #{stderr.to_f}."))
      end
    else

      result_message    = stderr
    end

    print_status(create_status(result_status, result_message))
    assertionResult
  end

  def self.create_status(status, message)

    "#{Time.new} #{status}: #{message}"
  end

  def self.print_status(message)

    $stderr.puts(message)
  end

  def self.im_compare(expected_path, received_path, diff_path)

    command = '/usr/local/bin/compare -metric MAE '
    command << Shellwords.escape(expected_path) + ' '
    command << Shellwords.escape(received_path) + ' '
    command << ( diff_path ? Shellwords.escape(diff_path) : 'null:' )

    _, _, stderr = Open3.popen3(command)
    stderr.read
  end
end
