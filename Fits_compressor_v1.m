function Fits_compressor_v1
%Fits_compressor: Removes non-illuminated frames from .fits movies acquired
%with Alternating Laser EXitation
clear all
close all
run('my_prefs.m')

%% choose colors
rgb={'red','green','blue'};
[colors,ok]=listdlg('PromptString', 'Select two colors to be compressed',...
                'ListString', rgb,...
                'OKString', 'Engage');
while ne(length(colors),2) && ok>0
    [colors,ok]=listdlg('PromptString', 'Select _TWO_ colors to be compressed',...
                'ListString', rgb,...
                'OKString', 'Engage');
end

channel = cell(2,1);
channel{1} = rgb{colors(1)};
channel{2} = rgb{colors(2)};

%% LOAD STACK OF MOVIES
pname=uigetdir(data_dir,'Choose the folder with all .fits files.');
files = cell(1,2);
for ch = 1:2
    files{ch} = pickFirstFitsFiles(pname, channel{ch}); 
end

N_movie = length(files{1});
if length(files{1}) ~= length(files{2})
    disp('WARNING: not same number of movie files!')
end

%% SET PARAMETER
button = questdlg('Assign parameters individually for each movie?');
options.Resize = 'off';
input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':']}; % sample options
input_default = {'2', '-1', '01', '10'};

if button(1) == 'N'
    params = inputdlg(input, 'All movies', 1, input_default, options);
end

first = ones(N_movie,1).*str2double(input_default{1});
last = ones(N_movie,1).*str2double(input_default{2});
sequences = cell(N_movie,size(channel,1));
for m = 1:N_movie
    if button(1) == 'Y'
        params = inputdlg(input, ['Movie #' num2str(m)], 1, input_default, options);
    end
    first(m) = round(str2double(params(1))); % first image to read from file
    last(m) = round(str2double(params(2))); % last image to read from file
    %determine sequences
    for ch = 1:size(sequences,2)
    sequences{m,ch} = zeros(1, size(params{2+ch},2));
        for i=1:size(params{2+ch},2)
            if(params{2+ch}(i) == '1')
                sequences{m,ch}(1,i) = 1;
            end
        end
    end
end
%% generate movie classes
movies = cell(N_movie,2);
for i=1:N_movie
    for ch = 1:2
    movies{i,ch} = movie(pname, files{ch}{i}, first(i), last(i), sequences{i,ch}); % pname, fname, first, last, sequence
    end
end

convert_objects = questdlg('Also convert movie objects?','Objects also?', 'Yes');
convert_objects = strcmp(convert_objects,'Yes');
if convert_objects
    [object_filename, object_path] = uigetfile(pname,'Select the old movie object file:');
end

%% Create and write movies
for m = 1:N_movie
    for ch = 1:2
        for i = 1:floor(length(movies{m,ch}.frames)/movies{m,ch}.N_frame_per_fits)
            % Whole 4095 frame movies
            mov_out = zeros(movies{m,ch}.sizeX,movies{m,ch}.sizeY,...
                movies{m,ch}.N_frame_per_fits, 'int32');
            frame_out = 0;
            for n = movies{m,ch}.frames((i-1)*movies{m,ch}.N_frame_per_fits+1:i*movies{m,ch}.N_frame_per_fits)
                % read Frame to tmp
                tmp = movies{m,ch}.readFrame(n);
                frame_out = frame_out + 1;
                % fill output
                mov_out(:,:,frame_out) = int32(tmp);
            end
            mov_out = int16(mov_out - 2^15);
            % Write output movie
            %disp(frame_out)
            display(['Writing compressed .fits file #' num2str(i) ' of ' ...
                num2str(ceil(length(movies{m,ch}.frames)/movies{m,ch}.N_frame_per_fits)) ...
                ' in movie #' num2str(m) ', channel ' num2str(ch)])
            fitswrite(mov_out, [pname filesep movies{m,ch}.fname{i}])
        end
        % Remaining frames (last movie)
        mov_out = zeros(movies{m,ch}.sizeX,movies{m,ch}.sizeY,...
            rem(length(movies{m,ch}.frames),movies{m,ch}.N_frame_per_fits), 'int32');
        frame_out = 0;
        for n = movies{m,ch}.frames(end-size(mov_out,3)+1:end)
            % read Frame to tmp
            tmp = movies{m,ch}.readFrame(n);
            frame_out = frame_out + 1;
            % fill output
            mov_out(:,:,frame_out) = int32(tmp);
        end
        mov_out = int16(mov_out - 2^15);
        % Write output movie
        %disp(frame_out)
        display(['Writing compressed .fits file #' num2str(i+1) ' of ' ...
            num2str(ceil(length(movies{m,ch}.frames)/movies{m,ch}.N_frame_per_fits)) ...
            ' in movie #' num2str(m) ', channel ' num2str(ch)])
        fitswrite(mov_out, [pname filesep movies{m,ch}.fname{i+1}])
        for k = i+2:length(movies{m,ch}.fname)
            display(['Deleting file: ' movies{m,ch}.fname{k}])
            delete([pname filesep movies{m,ch}.fname{k}])
        end
    end
end

%% Re-write movie object file
if convert_objects
    % create new movie objects
    for ch = 1:2
        files{ch} = pickFirstFitsFiles(pname, channel{ch}); 
    end
    for i=1:N_movie
        for ch = 1:2
            movies{i,ch} = movie(pname, files{ch}{i}, 1, -1, 1); % pname, fname, first, last, sequence
        end
    end
    % load old movie object file
    cd(object_path)
    load(object_filename, 'ch1', 'ch2')
    for m = 1:N_movie
        % ch1
        if ch1{m}.first == 2
            ch1{m}.first = 1;
            ch1{m}.last = movies{m,1}.last;
            ch1{m}.frames = movies{m,1}.frames;
            ch1{m}.mov_length = movies{m,1}.mov_length;            
        else
            display(['First frame in channel 1, movie ' num2str(m) ' is: ' num2str(ch1{m}.first)])
            warndlg(['Assign new values for ch1{' num2str(m) '} manually.'])
        end
        ch1{m}.sequence = 1;
        ch1{m}.fname = movies{m,1}.fname;
        ch1{m}.info = movies{m,1}.info;
        % ch2
        if ch2{m}.first == 2
            ch2{m}.first = 1;
            ch2{m}.last = movies{m,2}.last;
            ch2{m}.frames = movies{m,2}.frames;
            ch2{m}.mov_length = movies{m,2}.mov_length;
        else
            display(['First frame in channel 2, movie ' num2str(m) ' is: ' num2str(ch2{m}.first)])
            warndlg(['Assign new values for ch2{' num2str(m) '} manually.'])
        end
        ch2{m}.sequence = 1;
        ch2{m}.fname = movies{m,2}.fname;
        ch2{m}.info = movies{m,2}.info;
    end
    save([object_filename(1:end-4) '_new.mat'], 'ch1', 'ch2')
    display('New data saved.')
end      
display('Done')
end

