function Fits_compressor %( path_out )
%Fits_compressor: Removes non-illuminated frames from .fits movies acquired
%with Alternating Laser EXitation

%cd(path_out)
mov_dir = uigetdir(data_dir,'Choose the folder with the .fits files you want to compress');
cd(char(mov_dir))

%% choose colors
rgb={'red','green','blue'};
[colors,ok]=listdlg('PromptString', 'Select two colors to be analyzed',...
                'ListString', rgb,...
                'OKString', 'Engage');
while ne(length(colors),2) && ok>0
    [colors,ok]=listdlg('PromptString', 'Select _TWO_ colors to be analyzed',...
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
options.Resize = 'on';
input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':']}; % sample options
input_default = {'2', '-1', '01', '10'};

if button(1) == 'N'
tmp = inputdlg(input, 'All movies', 1, input_default, options);
end

first = ones(N_movie,1).*str2double(input_default{1});
last = ones(N_movie,1).*str2double(input_default{2});
sequences = cell(N_movie,size(channel,1));
for m = 1:N_movie
    if button(1) == 'Y'
        tmp = inputdlg(input, ['Movie #' num2str(m)], 1, input_default, options);
    end
    first(m) = round(str2double(tmp(1))); % first image to read from file
    last(m) = round(str2double(tmp(2))); % last image to read from file
    %determine sequences
    for ch = 1:size(sequences,2)
    sequences{m,ch} = zeros(1, size(tmp{2+ch},2));
        for i=1:size(tmp{2+ch},2)
            if(tmp{2+ch}(i) == '1')
                sequences{m,ch}(1,i) = 1;
            end
        end
    end
end
%% generate movie classes
movies = cell(N_movie,2);

for i=1:N_movie
    for ch = 1:2
    movies{i,ch} = movie(pname, files{ch}{i}, first(i), last(i), sequences{i,1}); % pname, fname, first, last, sequence
    movies{i,ch} = movie(pname, files{ch}{i}, first(i), last(i), sequences{i,2}); % pname, fname, first, last, sequence
    end
end
%{

%% Load data
load('movie_objects.mat')
%}

%% Prepare output
m = 1;
ch = 1;
mov_out = zeros(512,512,length(movies{m,ch}.frames(movies{m,ch}.frames<=4095)), 'uint16');


%% Fill output
movies{m,ch}.initRead;
go_on = 1;
a = 1;
while go_on
    [tmp, ~, go_on] = movies{m,ch}.readNext;
    
    tmp = uint16(tmp(:,:,:));

    b = a + size(tmp,3)-1;
    mov_out(:,:,a:b) = tmp;
    a = a + movies{m,ch}.N_read;
end
%mov_out = int16(mov_out - 2^15);

%% Write output movie
display('Writing output movie .fits file...')
fitswrite(mov_out, [mov_dir filesep movies{m,ch}.fname{1}(1:end-5) '_compressed.fits'])
display('Done')
end

